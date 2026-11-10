import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit
import UserNotifications
import ConduitCore

private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

@main enum EntryPoint {
    @MainActor static func main() {
        let args = CommandLine.arguments
        AppLocalization.configure(arguments: args)
        if let index = args.firstIndex(of: "--login-item"), args.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            do {
                switch args[index + 1] {
                case "enable": try LaunchAtLogin.setEnabled(true)
                case "disable": try LaunchAtLogin.setEnabled(false)
                case "status": break
                default: exit(64)
                }
                let data = try JSONSerialization.data(withJSONObject: LaunchAtLogin.report, options: .sortedKeys)
                print(String(data: data, encoding: .utf8)!); return
            } catch { print("Login item error: \((error as NSError).code)"); exit(1) }
        }
        if args.contains("--permission-status") || args.contains("--notification-check") || args.contains("--clear-notification-test") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task {
                let center=UNUserNotificationCenter.current()
                let settings=await center.notificationSettings()
                var output:[String:Any]=["notificationAuthorization":settings.authorizationStatus.rawValue,"bluetooth":ConnectionDiagnostics.permission.rawValue]
                if args.contains("--clear-notification-test") {
                    let tests = await center.deliveredNotifications().filter { $0.request.content.subtitle == "Conduit UI test" }
                    center.removeDeliveredNotifications(withIdentifiers: tests.map { $0.request.identifier })
                }
                if args.contains("--notification-check") {
                    let delivered=await center.deliveredNotifications().filter { $0.request.content.subtitle == "Conduit UI test" }
                    output["testNotifications"]=delivered.map { ["attachments":$0.request.content.attachments.count,"iconReadable":$0.request.content.attachments.first.map { FileManager.default.fileExists(atPath:$0.url.path) } ?? false] }
                }
                let data=try! JSONSerialization.data(withJSONObject:output,options:.sortedKeys)
                print(String(data:data,encoding:.utf8)!); exit(0)
            }
            RunLoop.main.run(); return
        }
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
            let names = ["platform-tools/adb", "scrcpy-server-v5.0.1", "conduit-companion.apk", "AppIcon.icns", "Assets.car", "en.lproj/Localizable.strings", "ru.lproj/Localizable.strings"]
            guard names.allSatisfy({ FileManager.default.fileExists(atPath: resources.appendingPathComponent($0).path) }),
                  let server = try? Data(contentsOf: resources.appendingPathComponent("scrcpy-server-v5.0.1")) else { exit(1) }
            guard Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "AppIcon",
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon",
                  let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.icns")), icon.isValid else { exit(6) }
            let hash = SHA256.hash(data: server).map { String(format: "%02x", $0) }.joined()
            guard hash == "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536" else { exit(2) }
            guard AppLocalization.validateBundle() else { exit(7) }
            print("Conduit \(appVersion): resources, server and both languages verified")
            return
        }
        if let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 {
            let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
            let model = ConduitModel(startMonitoring: false)
            if args.contains("--preview-error") { model.connectionError = L("Телефон сопряжён с Mac, но служба Conduit не найдена. На телефоне установи APK 0.2.3 или новее и нажми «Включить Bluetooth-соединение».") }
            app.appearance = NSAppearance(named: args.contains("--preview-dark") ? .darkAqua : .aqua)
            if args.contains("--preview-connected") {
                model.connected = true; model.companionReady = true; model.status = "Bluetooth · Xiaomi 15"
                model.bluetoothClipboardAuto = true; model.notificationAccess = true; model.notificationListenerConnected = true
                model.companionStatus = L("Уведомления подключены"); model.macNotificationPermission = .allowed; model.macBluetoothPermission = .allowed
            }
            if args.contains("--preview-notifications") {
                let source = "00000000-0000-0000-0000-000000000001"
                model.notificationSource = source; model.notificationSynced = true
                for (index, title) in ["Project update", "Transfer complete", "Meeting in 15 minutes"].enumerated() {
                    if let item = InboxNotification(source: source, event: ["key": "preview-\(index)", "instance": String(Int(Date().timeIntervalSince1970 * 1000) - index * 60000), "app": "Example", "title": title, "body": "Preview notification details", "dismissible": true, "replyable": true]) {
                        model.inbox.upsert(item)
                        if index == 1 { model.inbox.state(.pending, id: item.id, instance: item.instance) }
                    }
                }
            }
            if args.contains("--preview-permission-denied") { model.macNotificationPermission = .denied }
            if args.contains("--preview-permission-needed") { model.macNotificationPermission = .notAsked }
            let section: ConduitSection = args.contains("--preview-notifications") ? .notifications : args.contains("--preview-settings") ? .settings : (args.contains("--preview-files") ? .files : .overview)
            let previewWidth: CGFloat = args.contains("--preview-compact") ? 860 : 980
            let view = NSHostingView(rootView: MainView(model: model, initialSection: section).frame(width: previewWidth, height: 760))
            view.frame = NSRect(x: 0, y: 0, width: previewWidth, height: 760)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(4) }
            do { try png.write(to: URL(fileURLWithPath: args[index + 1])) } catch { exit(5) }
            print("Rendered Conduit interface preview")
            return
        }
        ConduitApp.main()
    }
}

struct ConduitApp: App {
    @AppStorage("language") private var language = "system"
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ConduitModel()

    var body: some Scene {
        WindowGroup("Conduit", id: "main") {
            MainView(model: model).frame(minWidth: 860, minHeight: 640)
                .environment(\.locale, Locale(identifier: AppLocalization.resolvedLanguage(language)))
                .onChange(of: language) { _ in model.refreshLocalizedPresentation(); AppDelegate.configureCategories() }
                .alert(L("Не удалось подключиться"), isPresented: $model.showConnectionError) {
                    Button(L("Скопировать диагностику")) { model.copyConnectionDiagnostics() }
                    Button(L("Понятно"), role: .cancel) { }
                } message: { Text(L(model.connectionError ?? L("Причина неизвестна. Скопируй диагностику."))) }
        }
        .defaultSize(width: 980, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L("Завершить Conduit")) { Task { await model.prepareToQuit(); NSApp.terminate(nil) } }.keyboardShortcut("q")
            }
        }
        MenuBarExtra {
            MenuView(model: model).environment(\.locale, Locale(identifier: AppLocalization.resolvedLanguage(language)))
        } label: {
            Image(nsImage: BrandMark.menuBarImage).renderingMode(.template).help("Conduit · " + model.status)
        }
    }
}

private struct MenuView: View {
    @AppStorage("language") private var language = "system"
    @ObservedObject var model: ConduitModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Conduit").font(.headline).id(language)
        Text(L(model.status))
        Divider()
        Toggle(L("Общий буфер обмена"), isOn: $model.clipboardEnabled)
        Toggle(L("Уведомления телефона"), isOn: $model.notificationsEnabled)
        Button(L("Отправить файлы…")) { Task { await model.chooseFiles() } }.disabled(!model.connected || model.transferBusy)
        Button(L("Открыть входящие")) { openInbox() }
        Divider()
        Button(L("Открыть Conduit")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(L("Отключиться")) { Task { await model.disconnect() } }.disabled(!model.connected || model.busy)
        Button(L("Завершить")) { Task { await model.prepareToQuit(); NSApp.terminate(nil) } }
    }
}

func openInbox() {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    let inbox = downloads.appendingPathComponent("Conduit", isDirectory: true)
    NSWorkspace.shared.open(FileManager.default.fileExists(atPath: inbox.path) ? inbox : downloads)
}
