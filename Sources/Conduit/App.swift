import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

@main enum EntryPoint {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--bluetooth-link-check"), args.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let output = BluetoothServiceCheck.checkLink(address:args[index + 1])
            if let data = try? JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]), let text = String(data:data,encoding:.utf8) { print(text) }
            return
        }
        if let index = args.firstIndex(of: "--bluetooth-service-check"), args.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let output = BluetoothServiceCheck.run(address: args[index + 1])
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if args.contains("--bluetooth-status") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let permission = ConnectionDiagnostics.permission
            let phones = permission == .allowed ? BluetoothChannel.pairedPhones() : []
            let output: [String: Any] = ["permission": permission.rawValue, "power": ConnectionDiagnostics.poweredOn as Any? ?? "unknown",
                "paired": phones.map { ["name": $0.name, "address": $0.id, "majorClass": Int($0.device.deviceClassMajor)] }]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if args.contains("--smoke-test") {
            let resources = Bundle.main.resourceURL!
            let names = ["platform-tools/adb", "scrcpy-server-v5.0.1", "conduit-companion.apk"]
            guard names.allSatisfy({ FileManager.default.fileExists(atPath: resources.appendingPathComponent($0).path) }),
                  let server = try? Data(contentsOf: resources.appendingPathComponent("scrcpy-server-v5.0.1")) else { exit(1) }
            let hash = SHA256.hash(data: server).map { String(format: "%02x", $0) }.joined()
            guard hash == "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536" else { exit(2) }
            print("Conduit \(appVersion): bundled ADB, companion APK and pinned scrcpy server verified")
            return
        }
        if let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 {
            let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
            let model = ConduitModel(startMonitoring: false)
            if args.contains("--preview-error") { model.connectionError = "Телефон сопряжён с Mac, но служба Conduit не найдена. На телефоне установи APK 0.2.3 или новее и нажми «Включить Bluetooth-соединение»." }
            let view = NSHostingView(rootView: MainView(model: model).frame(width: 700, height: 900))
            view.frame = NSRect(x: 0, y: 0, width: 700, height: 900)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(4) }
            do { try png.write(to: URL(fileURLWithPath: args[index + 1])) } catch { exit(5) }
            print("Rendered disconnected-state preview")
            return
        }
        ConduitApp.main()
    }
}

struct ConduitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ConduitModel()

    var body: some Scene {
        WindowGroup("Conduit", id: "main") {
            MainView(model: model).frame(minWidth: 640, minHeight: 640)
                .alert("Не удалось подключиться", isPresented: $model.showConnectionError) {
                    Button("Скопировать диагностику") { model.copyConnectionDiagnostics() }
                    Button("Понятно", role: .cancel) { }
                } message: { Text(model.connectionError ?? "Причина неизвестна. Скопируй диагностику.") }
        }
        .defaultSize(width: 700, height: 780)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Завершить Conduit") { Task { await model.disconnect(); NSApp.terminate(nil) } }.keyboardShortcut("q")
            }
        }
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.connected ? "link.circle.fill" : "link.circle")
        }
    }
}

private struct MenuView: View {
    @ObservedObject var model: ConduitModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Conduit").font(.headline)
        Text(model.status)
        Divider()
        Toggle("Общий буфер обмена", isOn: $model.clipboardEnabled)
        Toggle("Уведомления телефона", isOn: $model.notificationsEnabled)
        Button("Отправить файлы…") { Task { await model.chooseFiles() } }.disabled(!model.connected || model.transferBusy)
        Button("Открыть входящие") { openInbox() }
        Divider()
        Button("Открыть Conduit") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Отключиться") { Task { await model.disconnect() } }.disabled(!model.connected || model.busy)
        Button("Завершить") { Task { await model.disconnect(); NSApp.terminate(nil) } }
    }
}

private struct MainView: View {
    @ObservedObject var model: ConduitModel
    @State private var showWireless = false
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "link.circle.fill").font(.system(size: 46)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conduit").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Твой Android. Рядом с Mac.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("ПРОТОТИП \(appVersion)").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(8).background(.quaternary, in: Capsule())
                }

                Picker("Соединение", selection: $model.transport) {
                    ForEach(ConnectionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(model.connected || model.busy)
                if model.transport == .bluetooth {
                    bluetoothCard
                } else {
                card {
                    HStack {
                        Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                        Text(model.status).font(.headline).textSelection(.enabled)
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                    HStack {
                        Picker("Телефон", selection: $model.selectedSerial) {
                            if model.selectedSerial.isEmpty { Text("Выбери устройство").tag("") }
                            ForEach(model.devices) { device in
                                Text(device.name + (device.authorized ? "" : " · " + device.state)).tag(device.serial)
                            }
                        }.disabled(model.connected || model.busy)
                        if model.connected {
                            Button("Отключить") { Task { await model.disconnect() } }.disabled(model.busy)
                        } else {
                            Button("Подключить") { Task { await model.connect() } }
                                .buttonStyle(.borderedProminent).tint(.teal)
                                .disabled(model.busy || !model.devices.contains(where: { $0.serial == model.selectedSerial && $0.authorized }))
                        }
                    }
                    if model.devices.contains(where: { $0.state == "unauthorized" }) {
                        Label("Разблокируй телефон и разреши отладку для этого Mac.", systemImage: "lock.open").font(.callout)
                    }
                    if model.devices.isEmpty {
                        Text("Для первого подключения включи «Отладку по USB» на телефоне и подключи кабель. Для Wi-Fi открой настройку ниже.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Toggle("Подключаться снова, когда телефон вернётся", isOn: $model.autoReconnect).font(.callout)
                    DisclosureGroup("Подключение по Wi-Fi", isExpanded: $showWireless) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Android 11+: Настройки → Для разработчиков → Беспроводная отладка. Телефон и Mac должны быть в одной сети.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                TextField("IP:порт из «Сопряжение по коду»", text: $model.pairingAddress)
                                SecureField("Код", text: $model.pairingCode).frame(width: 90)
                                Button("Связать") { Task { await model.pairWireless() } }
                            }
                            HStack {
                                TextField("IP:порт с основного экрана отладки", text: $model.wirelessAddress)
                                Button("Найти телефон") { Task { await model.connectWireless() } }
                            }
                            Text("Порты сопряжения и подключения разные. После перезагрузки телефона адрес подключения может измениться.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !model.wirelessResult.isEmpty { Text(model.wirelessResult).font(.callout).textSelection(.enabled) }
                        }.textFieldStyle(.roundedBorder).padding(.top, 10)
                    }.font(.callout)
                }

                }

                card {
                    HStack(alignment: .top, spacing: 12) {
                        featureIcon("doc.on.clipboard", color: .teal)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Общий буфер обмена", isOn: $model.clipboardEnabled).font(.headline)
                            Text(model.transport == .bluetooth && !model.bluetoothClipboardAuto ? "Mac → телефон: автоматически. Для автобуфера с телефона включи Shizuku в Android-приложении; также есть ручная отправка." : "Скопируй текст на одном устройстве — вставь на другом. Новые копирования, без истории.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(model.connected && model.clipboardEnabled ? "Синхронизация включена" : "Синхронизация приостановлена")
                                .font(.caption).foregroundStyle(model.connected && model.clipboardEnabled ? .teal : .secondary)
                        }
                    }
                }

                card {
                    HStack(alignment: .top, spacing: 12) {
                        featureIcon("bell.badge", color: .orange)
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Уведомления телефона", isOn: $model.notificationsEnabled).font(.headline)
                            Text("Уведомления в macOS, ответы из баннера и закрытие на телефоне.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(model.companionStatus).font(.caption).foregroundStyle(.secondary)
                            if model.transport == .adb {
                            HStack {
                                Button("Установить на телефон") { Task { await model.startCompanion(install: true) } }
                                Button("Подключить") { Task { await model.startCompanion(install: false) } }
                                Button("Открыть на телефоне") { Task { await model.openPhoneApp() } }
                            }.disabled(!model.connected || model.busy)
                            }
                            Button("Разрешить уведомления в macOS") { Task { await model.requestMacNotifications() } }
                                .font(.callout)
                        }
                    }
                }

                card {
                    HStack(alignment: .top, spacing: 12) {
                        featureIcon("arrow.up.doc", color: .blue)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Файлы в обе стороны").font(.headline)
                            if !model.transferProgress.isEmpty { Text(model.transferProgress).font(.caption).foregroundStyle(.teal) }
                            Text("Перетащи файлы сюда. С телефона: «Поделиться» → Conduit. Полученные файлы появятся в Загрузках.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button(model.transferBusy ? "Передача…" : "Выбрать файлы…") { Task { await model.chooseFiles() } }
                                    .disabled(!model.connected || model.transferBusy)
                                Button("Открыть входящие") { openInbox() }
                            }
                        }
                    }
                    if targeted { Label("Отпусти, чтобы отправить на телефон", systemImage: "arrow.down.circle").foregroundStyle(.teal) }
                }
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? Color.teal : .clear, lineWidth: 2))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
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

                if !model.events.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("СОБЫТИЯ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(model.events.enumerated()), id: \.offset) { _, text in
                            Text(text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Text("Локальное соединение. Текст буфера не сохраняется. Защищённые уведомления Android может скрывать. Bluetooth: файлы до 100 МБ.")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var bluetoothCard: some View {
        card {
            HStack {
                Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                Text(model.status).font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            if model.busy {
                HStack {
                    Text("\(model.connectionStage) · \(model.connectionSeconds) с").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Отменить") { Task { await model.cancelConnection() } }
                }
            }
            if let error = model.connectionError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            Text("На телефоне открой Conduit и включи Bluetooth-соединение. Для первого запуска свяжи устройства в настройках Bluetooth.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Телефон", selection: $model.bluetoothAddress) {
                    Text("Выбери устройство").tag("")
                    ForEach(model.bluetoothPhones) { Text($0.name).tag($0.id) }
                }.disabled(model.connected || model.busy)
                Button("Обновить") { model.refreshBluetoothPhones() }.disabled(model.busy)
            }
            HStack {
                SecureField("Код Conduit с телефона · первый раз", text: $model.bluetoothCode).textFieldStyle(.roundedBorder)
                if model.connected {
                    Button("Отключить") { Task { await model.disconnect() } }.disabled(model.busy)
                } else {
                    Button("Подключить") { Task { await model.connectBluetooth() } }.buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(model.busy)
                }
            }
            Toggle("Подключаться снова, когда телефон вернётся", isOn: $model.autoReconnect).font(.callout)
            HStack {
                Button("Настройки Bluetooth") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                Button("Отправить APK по Bluetooth") { model.shareCompanionViaBluetooth() }
                Button("Забыть связь") { Task { await model.forgetBluetoothPhone() } }.disabled(model.busy)
            }.font(.callout)
            HStack {
                Button("Скопировать диагностику") { model.copyConnectionDiagnostics() }
                Button("Открыть журнал") { NSWorkspace.shared.activateFileViewerSelecting([ConnectionDiagnostics.url]) }
            }.font(.callout)
            Toggle("Автоматически переносить журнал Android на Mac", isOn:$model.autoDiagnostics).font(.callout)
            HStack {
                Button("Обновить журнал телефона") { model.requestAndroidDiagnostics() }.disabled(!model.connected || model.androidDiagnosticsPending)
                Button("Папка диагностики") { NSWorkspace.shared.open(ConnectionDiagnostics.androidDirectory) }
            }.font(.callout)
            Text(model.androidDiagnosticsStatus).font(.caption).foregroundStyle(.secondary)
            if model.connected && model.bluetoothDeviceLocked {
                Text("Телефон заблокирован. Android разрешит чтение буфера после разблокировки.").font(.caption).foregroundStyle(.orange)
            }
            Text("Android-приложение придёт в ZIP: распакуй и установи APK. Код Conduit — 8 цифр из «Связать новый Mac»; это отдельный код после системного сопряжения.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
    private func featureIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name).font(.system(size: 21)).foregroundStyle(color).frame(width: 30, height: 30)
    }
}

private func openInbox() {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    let inbox = downloads.appendingPathComponent("Conduit", isDirectory: true)
    NSWorkspace.shared.open(FileManager.default.fileExists(atPath: inbox.path) ? inbox : downloads)
}
