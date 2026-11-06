import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit
import UserNotifications

private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

@main enum EntryPoint {
    @MainActor static func main() {
        let args = CommandLine.arguments
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
            let names = ["platform-tools/adb", "scrcpy-server-v5.0.1", "conduit-companion.apk", "AppIcon.icns", "Assets.car"]
            guard names.allSatisfy({ FileManager.default.fileExists(atPath: resources.appendingPathComponent($0).path) }),
                  let server = try? Data(contentsOf: resources.appendingPathComponent("scrcpy-server-v5.0.1")) else { exit(1) }
            guard Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "AppIcon",
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon",
                  let icon = NSImage(contentsOf: resources.appendingPathComponent("AppIcon.icns")), icon.isValid else { exit(6) }
            let hash = SHA256.hash(data: server).map { String(format: "%02x", $0) }.joined()
            guard hash == "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536" else { exit(2) }
            print("Conduit \(appVersion): bundled ADB, companion APK and pinned scrcpy server verified")
            return
        }
        if let index = args.firstIndex(of: "--render-preview"), args.count > index + 1 {
            let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
            let model = ConduitModel(startMonitoring: false)
            if args.contains("--preview-error") { model.connectionError = "Телефон сопряжён с Mac, но служба Conduit не найдена. На телефоне установи APK 0.2.3 или новее и нажми «Включить Bluetooth-соединение»." }
            app.appearance = NSAppearance(named: args.contains("--preview-dark") ? .darkAqua : .aqua)
            if args.contains("--preview-connected") {
                model.connected = true; model.companionReady = true; model.status = "Bluetooth · Xiaomi 15"
                model.bluetoothClipboardAuto = true; model.notificationAccess = true; model.notificationListenerConnected = true
                model.companionStatus = "Уведомления подключены"; model.macNotificationPermission = .allowed; model.macBluetoothPermission = .allowed
            }
            if args.contains("--preview-permission-denied") { model.macNotificationPermission = .denied }
            if args.contains("--preview-permission-needed") { model.macNotificationPermission = .notAsked }
            let section: ConduitSection = args.contains("--preview-settings") ? .settings : (args.contains("--preview-files") ? .files : .overview)
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = ConduitModel()

    var body: some Scene {
        WindowGroup("Conduit", id: "main") {
            MainView(model: model).frame(minWidth: 860, minHeight: 640)
                .alert("Не удалось подключиться", isPresented: $model.showConnectionError) {
                    Button("Скопировать диагностику") { model.copyConnectionDiagnostics() }
                    Button("Понятно", role: .cancel) { }
                } message: { Text(model.connectionError ?? "Причина неизвестна. Скопируй диагностику.") }
        }
        .defaultSize(width: 980, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Завершить Conduit") { Task { await model.disconnect(); NSApp.terminate(nil) } }.keyboardShortcut("q")
            }
        }
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: BrandMark.menuBarImage).help("Conduit · " + model.status)
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

func openInbox() {
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    let inbox = downloads.appendingPathComponent("Conduit", isDirectory: true)
    NSWorkspace.shared.open(FileManager.default.fileExists(atPath: inbox.path) ? inbox : downloads)
}
