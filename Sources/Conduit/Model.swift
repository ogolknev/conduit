import AppKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
import ConduitCore

@MainActor final class ConduitModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var selectedSerial = ""
    @Published var connected = false { didSet { updateSynchronizationActivity() } }
    @Published var busy = false
    @Published var transferBusy = false
    @Published var companionReady = false
    @Published var notificationAccess = false
    @Published var status = "Подключи телефон, чтобы начать"
    @Published var companionStatus = "Нужен Android-компаньон"
    @Published var clipboardEnabled = true { didSet { pasteboardChange = NSPasteboard.general.changeCount; if connected { sendBridge(["type":"preferences", "clipboard":clipboardEnabled]) } } }
    @Published var notificationsEnabled = true
    @Published var events: [String] = []
    @Published var wirelessAddress = ""
    @Published var pairingAddress = ""
    @Published var pairingCode = ""
    @Published var wirelessResult = ""
    @Published var autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect") }
    }

    @Published var transport: ConnectionKind = .bluetooth
    @Published var bluetoothPhones: [BluetoothPhone] = []
    @Published var bluetoothAddress = UserDefaults.standard.string(forKey: "lastBluetoothPhone") ?? ""
    @Published var bluetoothCode = ""
    @Published var bluetoothClipboardAuto = false
    @Published var bluetoothDeviceLocked = false
    @Published var autoDiagnostics = UserDefaults.standard.object(forKey:"autoDiagnostics") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoDiagnostics,forKey:"autoDiagnostics"); if autoDiagnostics { requestAndroidDiagnostics() } }
    }
    @Published var androidDiagnosticsPending = false
    @Published var androidDiagnosticsStatus = "Журнал телефона ещё не получен"
    var androidDiagnosticsRequest = UUID()
    @Published var transferProgress = ""
    @Published var connectionError: String?
    @Published var showConnectionError = false
    @Published var connectionStage = ""
    @Published var connectionSeconds = 0
    var connectionAttempt: UUID?
    var bluetooth: BluetoothChannel?
    var bluetoothDecoder = JSONLineDecoder()
    var bluetoothSetupError: String?
    var bluetoothAuthenticationFailed = false
    var bluetoothReplies: [String: PendingBluetoothReply] = [:]
    var receivingBluetoothFile = false

    let adb: ADB?
    var sessionSerial: String?
    var serverProcess: Process?
    var control: LocalChannel?
    var bridge: LocalChannel?
    var controlDecoder = ScrcpyDecoder()
    var bridgeDecoder = JSONLineDecoder()
    var forwardedPorts: [UInt16] = []
    var sessionID = UUID()
    var receivedHandshake = false
    var setupError: String?
    var bridgeAuthenticated = false
    var bridgeToken = ""
    var pasteboardChange = NSPasteboard.general.changeCount
    var sequence: UInt64 = 0
    var monitor: Task<Void, Never>?
    var clipboardTimer: Timer?
    var heartbeat: Timer?
    var diagnosticsTimer: Timer?
    var connectionHeartbeat = ConnectionHeartbeat()
    var reconnectPolicy = BluetoothReconnectPolicy()
    var synchronizationActivity: NSObjectProtocol?
    var shouldReconnect = UserDefaults.standard.object(forKey: "bluetoothConnectionWanted") as? Bool
        ?? (UserDefaults.standard.string(forKey: "lastBluetoothPhone") != nil)
    var refreshing = false
    var companionBusy = false
    var didReportClipboardSize = false
    var companionWanted = false
    var activeFiles = Set<String>()
    var receivedFiles: [String] = UserDefaults.standard.stringArray(forKey: "receivedFiles") ?? []
    var controlAttemptID = UUID()
    var bridgeAttemptID = UUID()

    init(startMonitoring: Bool = true) {
        adb = ADB.locate().map(ADB.init)
        if adb == nil { status = "ADB не найден. Используй готовую сборку приложения." }
        guard startMonitoring else { return }
        ConnectionDiagnostics.record("launch", "version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") permission=\(ConnectionDiagnostics.permission.rawValue)")
        AppDelegate.onAction = { [weak self] action in
            guard let self, self.notificationsEnabled, self.companionReady else { return }
            self.sendBridge(action)
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollClipboard() }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.companionReady else { return }
                switch self.connectionHeartbeat.tick(at: ProcessInfo.processInfo.systemUptime) {
                case .timedOut:
                    ConnectionDiagnostics.record("heartbeat.timeout")
                    if self.transport == .bluetooth { self.bluetooth?.cancel(); self.bluetoothLost("Телефон не ответил"); return }
                    self.bridge?.cancel(); self.bridge = nil
                    self.companionReady = false
                    self.companionStatus = "Компаньон отключился. Нажми «Подключить»."
                case .ping, .resumedPing:
                    ConnectionDiagnostics.record("heartbeat.ping")
                    self.sendBridge(["type": "ping"])
                case .wait: break
                }
            }
        }
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in
            Task { @MainActor in guard let self, self.autoDiagnostics else { return }; self.requestAndroidDiagnostics() }
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.transport == .bluetooth {
                    self.refreshBluetoothPhones()
                    if self.shouldReconnect && self.autoReconnect && !self.connected && !self.busy,
                       self.reconnectPolicy.isDue(at: ProcessInfo.processInfo.systemUptime),
                       BluetoothTrust.token(for: self.bluetoothAddress) != nil { await self.connectBluetooth(automatic: true) }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                await self.refreshDevices()
                if self.shouldReconnect && self.autoReconnect && !self.connected && !self.busy,
                   self.devices.contains(where: { $0.serial == self.selectedSerial && $0.authorized }) {
                    await self.connect()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func log(_ event: String) {
        events.insert(event, at: 0)
        if events.count > 8 { events.removeLast(events.count - 8) }
    }

    private func updateSynchronizationActivity() {
        if connected && synchronizationActivity == nil {
            synchronizationActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Синхронизация Conduit с подключённым телефоном")
        } else if !connected, let activity = synchronizationActivity {
            ProcessInfo.processInfo.endActivity(activity); synchronizationActivity = nil
        }
    }

    func refreshDevices() async {
        guard let adb, !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        do {
            devices = AndroidDevice.parse(try await adb.run(["devices", "-l"]))
            if selectedSerial.isEmpty, let only = devices.first, devices.count == 1 { selectedSerial = only.serial }
        } catch { if !connected && !busy { status = error.localizedDescription } }
    }

    func connect() async {
        if transport == .bluetooth { await connectBluetooth(); return }
        guard let adb, !busy, !selectedSerial.isEmpty else { return }
        busy = true
        defer { busy = false }
        shouldReconnect = true
        await cleanup()
        let id = UUID(); sessionID = id
        let serial = selectedSerial; sessionSerial = serial
        status = "Открываю соединение…"
        do {
            guard let server = resource("scrcpy-server-v5.0.1") else { throw AppError("В сборке отсутствует сервер буфера обмена.") }
            _ = try await adb.run(["push", server.path, "/data/local/tmp/conduit-scrcpy.jar"], serial: serial, timeout: 30)
            guard sessionID == id else { return }
            let scid = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
            let port = try await adb.forward(socket: "scrcpy_" + scid, serial: serial)
            forwardedPorts.append(port)
            let process = Process()
            process.executableURL = adb.executable
            process.arguments = ["-s", serial, "shell", "CLASSPATH=/data/local/tmp/conduit-scrcpy.jar", "app_process", "/", "com.genymobile.scrcpy.Server", "5.0.1", "scid=" + scid,
                "video=false", "audio=false", "control=true", "tunnel_forward=true", "send_device_meta=false", "send_dummy_byte=true", "clipboard_autosync=true", "power_on=false", "cleanup=false", "log_level=error"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); serverProcess = process
            // adb may accept TCP before the remote abstract socket exists. Require the server's startup byte.
            var established = false
            for _ in 0..<20 {
                guard sessionID == id else { return }
                receivedHandshake = false; setupError = nil
                controlDecoder = ScrcpyDecoder()
                let attempt = UUID(); controlAttemptID = attempt
                let channel = LocalChannel(port: port); control = channel
                channel.onData = { [weak self] bytes in Task { @MainActor in
                    guard let self, self.controlAttemptID == attempt else { return }
                    self.receiveControl(bytes, session: id)
                } }
                channel.onClose = { [weak self] reason in Task { @MainActor in
                    guard let self, self.controlAttemptID == attempt else { return }
                    self.controlClosed(reason, session: id)
                } }
                do { try await channel.connect() } catch { setupError = error.localizedDescription }
                for _ in 0..<5 {
                    if receivedHandshake || setupError != nil { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if receivedHandshake && setupError == nil { established = true; break }
                channel.cancel(); control = nil
                if !process.isRunning { break }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            guard established else { throw AppError("Сервис буфера не запустился. Разблокируй телефон и проверь разрешение отладки.") }
            guard sessionID == id else { return }
            connected = true
            pasteboardChange = NSPasteboard.general.changeCount
            status = "Подключено · " + (devices.first(where: { $0.serial == serial })?.name ?? "Android")
            log("Телефон подключён. Синхронизируются новые копирования текста.")
            if companionWanted { await startCompanion(install: false) }
        } catch {
            guard sessionID == id else { return }
            await cleanup()
            status = error.localizedDescription
        }
    }

    func disconnect() async {
        guard !busy else { return }
        busy = true; shouldReconnect = false
        if transport == .bluetooth { UserDefaults.standard.set(false, forKey: "bluetoothConnectionWanted") }
        await cleanup()
        status = "Отключено"
        busy = false
    }

    func cleanup() async {
        sessionID = UUID()
        bluetooth?.cancel(); bluetooth = nil; bluetoothClipboardAuto = false; bluetoothDeviceLocked = false
        androidDiagnosticsPending = false; androidDiagnosticsRequest = UUID()
        let replies = bluetoothReplies; bluetoothReplies.removeAll()
        for reply in replies.values { reply.timeout.cancel(); reply.continuation.resume(throwing: AppError("Соединение закрыто")) }
        controlAttemptID = UUID(); bridgeAttemptID = UUID()
        control?.cancel(); bridge?.cancel(); control = nil; bridge = nil
        serverProcess?.terminate(); serverProcess = nil
        connected = false; companionReady = false; bridgeAuthenticated = false; connectionHeartbeat.reset()
        companionStatus = "Нужен Android-компаньон"
        let ports = forwardedPorts; forwardedPorts = []
        let serial = sessionSerial; sessionSerial = nil
        if let adb, let serial {
            for port in ports { _ = try? await adb.run(["forward", "--remove", "tcp:\(port)"], serial: serial, timeout: 3) }
        }
    }

    func receiveControl(_ bytes: Data, session id: UUID) {
        guard sessionID == id else { return }
        var payload = bytes
        if !receivedHandshake {
            guard payload.first == 0 else { controlClosed("Некорректное начало канала", session: id); return }
            receivedHandshake = true; payload.removeFirst()
        }
        do {
            for message in try controlDecoder.append(payload) {
                if case .clipboard(let text) = message, clipboardEnabled, connected {
                    let board = NSPasteboard.general
                    if board.string(forType: .string) != text {
                        board.clearContents(); board.setString(text, forType: .string)
                    }
                    pasteboardChange = board.changeCount
                }
            }
        } catch { controlClosed("Ошибка протокола буфера обмена", session: id) }
    }

    func controlClosed(_ reason: String, session id: UUID) {
        guard sessionID == id else { return }
        setupError = reason
        guard connected, !busy else { return }
        Task {
            busy = true
            await cleanup()
            status = "Связь потеряна. Ожидаю телефон…"
            busy = false
        }
    }

    func pollClipboard() {
        let board = NSPasteboard.general
        guard board.changeCount != pasteboardChange else { return }
        pasteboardChange = board.changeCount
        guard clipboardEnabled, connected else { return }
        let privateTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        guard !(board.types ?? []).contains(where: { privateTypes.contains($0.rawValue) }),
              let text = board.string(forType: .string) else { return }
        do {
            sequence &+= 1
            if transport == .bluetooth {
                guard text.utf8.count <= ScrcpyDecoder.maxTextBytes else { throw ProtocolError.oversized }
                ConnectionDiagnostics.record("clipboard.to.phone")
                sendBridge(["type":"clipboard", "text":text])
            } else { control?.send(try ScrcpyEncoder.clipboard(text, sequence: sequence)) }
            didReportClipboardSize = false
        } catch {
            if !didReportClipboardSize { log("Текст больше 256 КБ. Отправь его файлом."); didReportClipboardSize = true }
        }
    }

    func startCompanion(install: Bool) async {
        guard let adb, let serial = sessionSerial, connected, !companionBusy else { return }
        companionBusy = true; defer { companionBusy = false }
        let id = sessionID
        companionWanted = true
        do {
            if install {
                companionStatus = "Устанавливаю приложение на телефон…"
                guard let apk = resource("conduit-companion.apk") else { throw AppError("В сборке отсутствует Android APK.") }
                _ = try await adb.run(["install", "-r", apk.path], serial: serial, timeout: 90)
            }
            guard sessionID == id else { return }
            companionStatus = "Соединяюсь с компаньоном…"
            bridgeToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            _ = try await adb.run(["shell", "am", "start-foreground-service", "-n", "dev.conduit.bridge/.BridgeService", "--es", "token", bridgeToken], serial: serial)
            if install { _ = try await adb.run(["shell", "am", "start", "-n", "dev.conduit.bridge/.MainActivity"], serial: serial) }
            let port = try await adb.forward(socket: "conduit.bridge", serial: serial)
            guard sessionID == id else { _ = try? await adb.run(["forward", "--remove", "tcp:\(port)"], serial: serial); return }
            forwardedPorts.append(port)
            bridge?.cancel()
            bridgeDecoder = JSONLineDecoder(); bridgeAuthenticated = false
            let attempt = UUID(); bridgeAttemptID = attempt
            let channel = LocalChannel(port: port); bridge = channel
            channel.onData = { [weak self] bytes in Task { @MainActor in
                guard let self, self.bridgeAttemptID == attempt else { return }
                self.receiveBridge(bytes, session: id)
            } }
            channel.onClose = { [weak self] _ in Task { @MainActor in
                guard let self, self.sessionID == id, self.bridgeAttemptID == attempt else { return }
                self.companionReady = false; self.bridgeAuthenticated = false
                self.companionStatus = "Компаньон отключился. Нажми «Подключить»."
            } }
            try await Task.sleep(nanoseconds: 400_000_000)
            try await channel.connect()
            channel.sendJSON(["type": "hello", "token": bridgeToken, "protocol": 1])
            for _ in 0..<30 {
                if bridgeAuthenticated { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard bridgeAuthenticated else { throw AppError("Компаньон не подтвердил соединение. Открой его на телефоне и повтори.") }
        } catch { if sessionID == id { companionStatus = error.localizedDescription; companionReady = false } }
    }

    func receiveBridge(_ data: Data, session id: UUID) {
        guard sessionID == id else { return }
        do {
            for event in try bridgeDecoder.append(data) {
                guard let type = event["type"] as? String else { continue }
                if !bridgeAuthenticated {
                    guard type == "ready", event["protocol"] as? Int == 1 else { bridge?.cancel(); return }
                    bridgeAuthenticated = true; companionReady = true; connectionHeartbeat.reset()
                }
                switch type {
                case "ready", "status":
                    notificationAccess = event["notificationAccess"] as? Bool == true
                    companionStatus = notificationAccess ? "Уведомления подключены" : "Разреши доступ к уведомлениям на телефоне"
                case "pong": connectionHeartbeat.acknowledge(); ConnectionDiagnostics.record("heartbeat.pong")
                case "notification":
                    guard notificationsEnabled, event["snapshot"] as? Bool != true else { continue }
                    Task { do { try await PhoneNotifications.show(event) } catch { log("macOS не показала уведомление. Проверь разрешения приложения.") } }
                case "removed":
                    if let key = event["key"] as? String { PhoneNotifications.remove(key) }
                case "file":
                    Task { await receiveFile(event) }
                case "result":
                    if event["ok"] as? Bool == false { log(event["message"] as? String ?? "Действие не выполнено на телефоне") }
                default: break
                }
            }
        } catch {
            bridge?.cancel(); companionReady = false
            companionStatus = "Ошибка канала уведомлений"
        }
    }

    func requestMacNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            log(allowed ? "macOS разрешила уведомления" : "Уведомления отключены в настройках macOS")
        } catch { log(error.localizedDescription) }
    }

    func openPhoneApp() async {
        guard let adb, let serial = sessionSerial else { return }
        _ = try? await adb.run(["shell", "am", "start", "-n", "dev.conduit.bridge/.MainActivity"], serial: serial)
    }

    func chooseFiles() async {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { await sendFiles(panel.urls) }
    }

    func sendFiles(_ urls: [URL]) async {
        if transport == .bluetooth { await sendBluetoothFiles(urls); return }
        guard let adb, let serial = sessionSerial, connected, !transferBusy else { return }
        transferBusy = true; defer { transferBusy = false }
        do {
            _ = try await adb.run(["shell", "mkdir", "-p", "/sdcard/Download/Conduit"], serial: serial)
            for url in urls {
                let file = url.standardizedFileURL
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { log("Папки пока не поддерживаются. Можно отправить ZIP."); continue }
                let destination = "/sdcard/Download/Conduit/" + UUID().uuidString.prefix(8) + "_" + FilePolicy.safeName(file.lastPathComponent)
                log("Передаю: " + file.lastPathComponent)
                _ = try await adb.run(["push", file.path, destination], serial: serial, timeout: 3600)
                log("На телефоне: Download/Conduit/" + destination.components(separatedBy: "/").last!)
            }
        } catch { log("Передача не завершена: " + error.localizedDescription) }
    }

    func receiveFile(_ event: [String: Any]) async {
        if transport == .bluetooth { await receiveBluetoothFile(event); return }
        guard let adb, let serial = sessionSerial, companionReady,
              let path = event["path"] as? String, FilePolicy.allowedRemoteFile(path),
              let size = event["size"] as? NSNumber, size.int64Value >= 0, size.int64Value <= 1_073_741_824 else { return }
        // Shares are explicit actions on the phone. Copy via an isolated temporary directory before publishing.
        let name = FilePolicy.safeName(event["name"] as? String ?? "file")
        let key = path.components(separatedBy: "/").last ?? "file"
        if receivedFiles.contains(key) { sendBridge(["type": "fileReceived", "name": key]); return }
        guard !activeFiles.contains(key) else { return }
        activeFiles.insert(key); defer { activeFiles.remove(key) }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Conduit", isDirectory: true)
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("conduit-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stage) }
            let partial = stage.appendingPathComponent("payload")
            _ = try await adb.run(["pull", path, partial.path], serial: serial, timeout: 3600)
            let actual = try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard actual.map(Int64.init) == size.int64Value else { throw AppError("Размер полученного файла не совпал.") }
            let destination = folder.appendingPathComponent(UUID().uuidString.prefix(8) + "_" + name)
            try FileManager.default.moveItem(at: partial, to: destination)
            receivedFiles.append(key)
            if receivedFiles.count > 256 { receivedFiles.removeFirst(receivedFiles.count - 256) }
            UserDefaults.standard.set(receivedFiles, forKey: "receivedFiles")
            sendBridge(["type": "fileReceived", "name": key])
            log("Получен: " + name)
        } catch { log("Не удалось получить файл: " + error.localizedDescription) }
    }

    func pairWireless() async {
        guard let adb, validAddress(pairingAddress), pairingCode.count == 6, pairingCode.allSatisfy(\.isNumber) else {
            wirelessResult = "Введи адрес сопряжения IP:порт и шестизначный код с телефона."; return
        }
        do {
            let result = try await adb.run(["pair", pairingAddress, pairingCode], timeout: 30)
            guard result.contains("Successfully paired") else { throw AppError(result) }
            pairingCode = ""
            wirelessResult = "Сопряжение выполнено. Теперь введи адрес подключения."
        } catch { wirelessResult = error.localizedDescription }
    }

    func connectWireless() async {
        guard let adb, validAddress(wirelessAddress) else { wirelessResult = "Нужен адрес IP:порт с экрана беспроводной отладки."; return }
        do {
            let result = try await adb.run(["connect", wirelessAddress], timeout: 20)
            guard result.contains("connected to") else { throw AppError(result) }
            selectedSerial = wirelessAddress
            await refreshDevices()
            wirelessResult = "Телефон найден. Можно подключаться."
        } catch { wirelessResult = error.localizedDescription }
    }

    func validAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = UInt16(parts[1]), port > 0 else { return false }
        return !parts[0].isEmpty && parts[0].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") } && !parts[0].hasPrefix("-")
    }
    func resource(_ name: String) -> URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent(name)
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }
}
