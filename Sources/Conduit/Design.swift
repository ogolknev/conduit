import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The same palette, spacing, and hierarchy are used by the Android companion.
private enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xFFFFFF, 0x151515)
    static let surface = adaptive(0xFFFFFF, 0x1C1C1C)
    static let ink = adaptive(0x191919, 0xF2F2F2)
    static let muted = adaptive(0x696969, 0xABABAB)
    static let accent = adaptive(0x202020, 0xEDEDED)
    static let soft = adaptive(0xF3F3F3, 0x292929)
    static let line = adaptive(0xE8E8E8, 0x333333)
    static let success = adaptive(0x23834C, 0x76D39A)
    static let warning = adaptive(0x97640F, 0xEAC17A)
    static let error = adaptive(0xC83B3B, 0xF29696)
}

enum ConduitSection: String, CaseIterable {
    case overview = "Устройства", files = "Файлы", settings = "Настройки"
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .files: return "folder"; case .settings: return "slider.horizontal.3" }
    }
}

private struct ConduitMark: View {
    var body: some View {
        Canvas { context, size in
            let u = size.width / 24
            context.fill(Path(roundedRect: CGRect(x: u, y: u, width: 22*u, height: 22*u), cornerRadius: 5*u), with: .color(Palette.accent))
            for x in [6.0, 13.5] {
                context.stroke(Path(roundedRect: CGRect(x: x*u, y: 7*u, width: 4.5*u, height: 10*u), cornerRadius: 1.2*u), with: .color(Palette.canvas), lineWidth: 1.25*u)
            }
            var bridge = Path(); bridge.move(to: CGPoint(x: 10.5*u, y: 12*u)); bridge.addLine(to: CGPoint(x: 13.5*u, y: 12*u))
            context.stroke(bridge, with: .color(Palette.canvas), lineWidth: 1.25*u)
        }.frame(width: 32, height: 32).accessibilityHidden(true)
    }
}

private struct ActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(primary ? Palette.canvas : Palette.ink)
            .background(primary ? Palette.accent : Palette.soft, in: RoundedRectangle(cornerRadius: 7))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct MainView: View {
    @ObservedObject var model: ConduitModel
    @State private var section: ConduitSection
    @State private var connectionSheet = false
    @State private var targeted = false
    @State private var forgetConfirmation = false
    @State private var showWireless = false

    init(model: ConduitModel, initialSection: ConduitSection = .overview) {
        self.model = model; _section = State(initialValue: initialSection)
    }

    private var deviceName: String {
        if model.transport == .bluetooth {
            return model.bluetoothPhones.first(where: { $0.id == model.bluetoothAddress })?.name
                ?? (model.connected ? model.status.replacingOccurrences(of: "Bluetooth · ", with: "") : "Android")
        }
        return model.devices.first(where: { $0.serial == model.selectedSerial })?.name ?? "Android"
    }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Text(section.rawValue).font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                        Spacer()
                        statusPill
                    }.padding(.bottom, 5)
                    switch section { case .overview: overview; case .files: files; case .settings: settings }
                }.padding(32).frame(maxWidth: 860, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(Palette.ink).background(Palette.canvas).tint(Palette.accent)
        .sheet(isPresented: $connectionSheet) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Подключить телефон").font(.system(size: 24, weight: .semibold))
                    Spacer()
                    Button { connectionSheet = false } label: { Image(systemName: "xmark").padding(8) }.buttonStyle(.plain).accessibilityLabel("Закрыть")
                }
                connectionControls
                if let error = model.connectionError { notice(error, icon: "exclamationmark.triangle", warning: true) }
                connectionAction
            }.padding(30).frame(width: 500).background(Palette.canvas).tint(Palette.accent)
        }
        .task { await model.refreshSystemPermissions() }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refreshSystemPermissions() } }
        .onChange(of: model.connected) { connected in if connected { connectionSheet = false } }
        .confirmationDialog("Забыть связь с телефоном?", isPresented: $forgetConfirmation) {
            Button("Забыть связь", role: .destructive) { Task { await model.forgetBluetoothPhone() } }
        } message: { Text("Для следующего подключения потребуется новый код Conduit с телефона.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 11) { ConduitMark(); Text("Conduit").font(.system(size: 19, weight: .semibold)).fixedSize() }.padding(.top, 14)
            VStack(spacing: 7) {
                ForEach(ConduitSection.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        HStack(spacing: 11) {
                            LineIcon(item.icon).foregroundStyle(Palette.ink).frame(width: 20, height: 20)
                            Text(item.rawValue).font(.system(size: 14, weight: section == item ? .semibold : .medium)).lineLimit(1)
                            Spacer()
                        }.padding(.horizontal, 14) .padding(.vertical, 11)
                            .foregroundStyle(section == item ? Palette.accent : Palette.muted)
                            .background(section == item ? Palette.soft : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label("Локальное соединение", systemImage: "lock").font(.system(size: 11)).lineSpacing(2)
                Text("Conduit \(version)").font(.system(size: 10)).padding(.top, 5)
            }.foregroundStyle(Palette.muted).padding(.horizontal, 8)
        }.padding(20).frame(width: 216).background(Palette.soft.opacity(0.55))
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle().fill(model.connected ? Palette.success : Palette.muted.opacity(0.5)).frame(width: 6, height: 6)
            Text(model.connected ? "Подключено · \(model.transport.rawValue)" : (model.busy ? "Подключение…" : "Нет соединения"))
                .font(.system(size: 11, weight: .medium))
        }.foregroundStyle(model.connected ? Palette.success : Palette.muted).padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color.clear)
    }

    private var overview: some View {
        Group {
            panel {
                HStack(spacing: 24) {
                    LineIcon("phone").foregroundStyle(Palette.accent).frame(width: 40, height: 56)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.connected ? deviceName : (model.busy ? "Подключение" : "Телефон не подключён"))
                            .font(.system(size: 20, weight: .medium))
                        Text(model.connected ? "Подключён по \(model.transport.rawValue)" : "Запустите Conduit на Android.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(2)
                        if model.connected {
                            Button("Отключить") { Task { await model.disconnect() } }.buttonStyle(ActionStyle())
                        } else {
                            Button(model.busy ? "Показать подключение" : "Подключить телефон") { connectionSheet = true }.buttonStyle(ActionStyle(primary: true))
                        }
                    }
                    Spacer(minLength: 0)
                }
                if model.busy { progress }
                if let error = model.connectionError { notice(error, icon: "exclamationmark.triangle", warning: true) }
                if model.connected && model.bluetoothDeviceLocked {
                    notice("Телефон заблокирован. Буфер обновится после разблокировки.", icon: "lock")
                }
            }
            sectionLabel("СИНХРОНИЗАЦИЯ")
            VStack(spacing: 0) {
                featureRow("doc.on.clipboard", title: "Буфер обмена", detail: clipboardDetail, stateColor: model.connected && model.clipboardEnabled ? (model.transport == .adb || model.bluetoothClipboardAuto ? Palette.success : Palette.warning) : Palette.muted, isOn: $model.clipboardEnabled)
                Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 72)
                featureRow("bell", title: "Уведомления", detail: notificationDetail, stateColor: model.connected && model.notificationsEnabled ? (model.notificationAccess && model.notificationListenerConnected && model.macNotificationPermission == .allowed ? Palette.success : Palette.warning) : Palette.muted, isOn: $model.notificationsEnabled)
            }.padding(6).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Передача файлов").font(.system(size: 14, weight: .medium))
                    Text("Передача между Mac и Android.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { section = .files } label: { Label("Открыть файлы", systemImage: "arrow.up.right") }.buttonStyle(ActionStyle())
            }.padding(.horizontal, 3)
        }
    }

    private var notificationDetail: String {
        if !model.notificationsEnabled { return "Передача отключена" }
        if !model.connected { return "Ожидание соединения" }
        if !model.notificationAccess { return "Требуется доступ Android" }
        if !model.notificationListenerConnected { return "Служба Android переподключается" }
        if model.macNotificationPermission == .quiet { return "Баннеры отключены в macOS" }
        if !model.macNotificationPermission.allowsDelivery { return "Требуется доступ macOS" }
        return "Уведомления Android → Mac"
    }
    private var clipboardDetail: String {
        if !model.clipboardEnabled { return "Синхронизация приостановлена" }
        if !model.connected { return "Ожидание соединения" }
        if model.transport == .bluetooth && !model.bluetoothClipboardAuto { return "Mac → Android · Обратная передача требует Shizuku" }
        return "Передача текста между устройствами"
    }

    private var files: some View {
        Group {
            VStack(spacing: 18) {
                LineIcon("upload").frame(width: 32, height: 36).foregroundStyle(Palette.muted).padding(10)
                Text(targeted ? "Отпустите файлы для отправки" : "Перетащите файлы в эту область").font(.system(size: 20, weight: .medium))
                Text(model.connected ? "До 100 МБ на файл по Bluetooth" : "Для передачи требуется соединение")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                Button(model.transferBusy ? "Передача…" : "Выбрать файлы") { Task { await model.chooseFiles() } }
                    .buttonStyle(ActionStyle(primary: true)).disabled(!model.connected || model.transferBusy)
                if !model.transferProgress.isEmpty { Text(model.transferProgress).font(.callout).foregroundStyle(Palette.accent) }
            }.frame(maxWidth: .infinity).padding(.vertical, 45)
                .background(targeted ? Palette.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Palette.accent : Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted, perform: acceptFiles)
            panel {
                HStack {
                    LineIcon("download").frame(width: 24, height: 24).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Входящие").font(.system(size: 14, weight: .medium))
                        Text("Загрузки / Conduit").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("Открыть папку", action: openInbox).buttonStyle(ActionStyle())
                }
            }
            Text("На Android: файл → Поделиться → Conduit.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            if !model.events.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ПОСЛЕДНИЕ СОБЫТИЯ").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted)
                    ForEach(Array(model.events.prefix(4).enumerated()), id: \.offset) { _, event in Text(event).font(.system(size: 12)).textSelection(.enabled) }
                }
            }
        }
    }

    private var settings: some View {
        Group {
            sectionLabel("СОЕДИНЕНИЕ")
            panel {
                HStack {
                    HStack(spacing: 10) { LineIcon("phone").frame(width: 20, height: 22); Text(model.connected ? deviceName : "Телефон").font(.system(size: 14, weight: .medium)) }
                    Spacer()
                    Button(model.connected ? "Отключить" : "Настроить") {
                        if model.connected { Task { await model.disconnect() } } else { connectionSheet = true }
                    }.buttonStyle(ActionStyle())
                }
                Divider().overlay(Palette.line)
                settingToggle("Автоматическое подключение", isOn: $model.autoReconnect)
                HStack {
                    Text("Доступ Bluetooth").font(.system(size:13)); Spacer()
                    Text(model.macBluetoothPermission == .allowed ? "Разрешён" : model.macBluetoothPermission == .unknown ? "Не запрошен" : "Не разрешён").font(.system(size:12)).foregroundStyle(model.macBluetoothPermission == .allowed ? Palette.success : Palette.warning)
                }
                if model.transport == .bluetooth {
                    HStack {
                        Button("Настройки Bluetooth") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                        Spacer()
                        Button("Забыть связь") { forgetConfirmation = true }.disabled(model.busy || model.bluetoothAddress.isEmpty)
                    }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            sectionLabel("УВЕДОМЛЕНИЯ")
            panel {
                Text(model.transport == .bluetooth ? (model.connected ? (model.notificationAccess ? (model.notificationListenerConnected ? "Доступ на Android разрешён" : "Доступ выдан, служба подключается") : "Требуется разрешение на Android") : "Нет соединения с Android") : model.companionStatus).font(.system(size: 13)).foregroundStyle(model.connected ? (model.notificationAccess && model.notificationListenerConnected ? Palette.success : Palette.warning) : Palette.muted)
                HStack {
                    VStack(alignment:.leading,spacing:5) {
                        Text("Уведомления macOS").font(.system(size:13,weight:.medium))
                        Text(model.macNotificationPermission.title).font(.system(size:12)).foregroundStyle(model.macNotificationPermission == .allowed ? Palette.success : model.macNotificationPermission == .denied || model.macNotificationPermission == .notAsked || model.macNotificationPermission == .quiet ? Palette.warning : Palette.muted)
                    }
                    Spacer()
                    Button(model.macNotificationsRequesting ? "Проверка…" : model.macNotificationPermission.actionTitle) { Task { await model.requestMacNotifications() } }.buttonStyle(ActionStyle()).disabled(model.macNotificationsRequesting || model.macNotificationPermission == .checking)
                }
                if model.transport == .adb {
                    HStack {
                        Button("Установить на телефон") { Task { await model.startCompanion(install: true) } }
                        Button(model.companionReady ? "Компаньон подключён" : "Подключить компаньон") { Task { await model.startCompanion(install: false) } }.disabled(model.companionReady)
                    }.disabled(!model.connected || model.busy)
                    Button("Открыть Conduit на телефоне") { Task { await model.openPhoneApp() } }.disabled(!model.connected)
                } else { Text("На Android доступ включается в Conduit → Настройки → Уведомления.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
            }
            sectionLabel("ДИАГНОСТИКА")
            panel {
                settingToggle("Сохранять журнал телефона на Mac", isOn: $model.autoDiagnostics)
                Text("После подключения и раз в минуту. Без содержимого буфера и уведомлений.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                HStack {
                    Button(model.androidDiagnosticsPending ? "Запрос…" : "Обновить") { model.requestAndroidDiagnostics() }.disabled(!model.connected || model.androidDiagnosticsPending || model.transport != .bluetooth)
                    Button("Открыть папку") { NSWorkspace.shared.open(ConnectionDiagnostics.androidDirectory) }
                    Button("Скопировать отчёт") { model.copyConnectionDiagnostics() }
                }.buttonStyle(ActionStyle())
                Text(model.androidDiagnosticsStatus).font(.system(size: 11)).foregroundStyle(Palette.muted)
                DisclosureGroup("Последние события") {
                    VStack(alignment: .leading, spacing: 7) { ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in Text(event).font(.system(size: 11)).textSelection(.enabled) } }.padding(.top, 10)
                }.font(.system(size: 12))
            }
            sectionLabel("CONDUIT \(version)")
            HStack {
                Text("Локальная связь. Буфер без истории.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Отправить APK") { model.shareCompanionViaBluetooth() }.buttonStyle(.link)
            }
        }
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Способ связи", selection: $model.transport) {
                ForEach(ConnectionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(model.connected || model.busy)
            if model.transport == .bluetooth {
                Text("1. Сопряжение устройств в настройках Bluetooth.\n2. На Android: Conduit → «Связать Mac».\n3. Выбор устройства и ввод кода ниже.")
                    .font(.system(size: 13)).lineSpacing(7).foregroundStyle(Palette.muted)
                HStack {
                    Picker("Телефон", selection: $model.bluetoothAddress) {
                        Text("Выбери устройство").tag("")
                        ForEach(model.bluetoothPhones) { Text($0.name).tag($0.id) }
                    }.disabled(model.busy || model.connected)
                    Button { model.refreshBluetoothPhones() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Обновить список устройств")
                }
                if BluetoothTrust.token(for: model.bluetoothAddress) == nil {
                    SecureField("Код Conduit (8 цифр)", text: $model.bluetoothCode).textFieldStyle(.roundedBorder).disabled(model.busy)
                } else { Label("Устройство авторизовано. Код не требуется.", systemImage: "checkmark.shield").font(.system(size: 12)).foregroundStyle(Palette.accent) }
                Button("Открыть настройки Bluetooth") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }.buttonStyle(.link)
            } else {
                Picker("Телефон", selection: $model.selectedSerial) {
                    Text("Выбери устройство").tag("")
                    ForEach(model.devices) { Text($0.name + ($0.authorized ? "" : " · " + $0.state)).tag($0.serial) }
                }.disabled(model.busy || model.connected)
                Text("Для USB требуется отладка Android и разрешение доступа для Mac.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                DisclosureGroup("Беспроводная отладка", isExpanded: $showWireless) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Android → Для разработчиков → Беспроводная отладка. Оба устройства должны быть в одной сети.").font(.system(size: 12))
                        HStack { TextField("IP:порт сопряжения", text: $model.pairingAddress); SecureField("Код", text: $model.pairingCode).frame(width: 80); Button("Связать") { Task { await model.pairWireless() } } }
                        HStack { TextField("IP:порт подключения", text: $model.wirelessAddress); Button("Найти") { Task { await model.connectWireless() } } }
                        Text("Порты сопряжения и подключения разные.").font(.caption)
                        if !model.wirelessResult.isEmpty { Text(model.wirelessResult).font(.caption).textSelection(.enabled) }
                    }.textFieldStyle(.roundedBorder).padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder private var connectionAction: some View {
        if model.busy { progress } else {
            HStack { Spacer(); Button("Подключить") { Task { await model.connect() } }.buttonStyle(ActionStyle(primary: true)).disabled(model.connected) }
        }
    }
    private var progress: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(model.connectionStage) · \(model.connectionSeconds) с").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Spacer()
            Button("Отменить") { Task { await model.cancelConnection() } }.buttonStyle(.link)
        }
    }
    private func sectionLabel(_ title: String) -> some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.muted).padding(.bottom, -14) }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).accessibilityLabel(title) }
    }
    private func featureRow(_ icon: String, title: String, detail: String, stateColor: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            LineIcon(icon).foregroundStyle(Palette.accent).frame(width: 32, height: 24)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 14, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(stateColor).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 5)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).accessibilityLabel(title)
        } .padding(16)
    }
    private func notice(_ text: String, icon: String, warning: Bool = false) -> some View {
        Label(text, systemImage: icon).font(.system(size: 12)).foregroundStyle(warning ? Palette.error : Palette.warning)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
    private func acceptFiles(_ providers: [NSItemProvider]) -> Bool {
        guard model.connected && !model.transferBusy else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url) }
                        else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url { urls.append(url) }
            }
            await model.sendFiles(urls)
        }
        return true
    }
}
