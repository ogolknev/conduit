import Foundation
import AppKit
import ConduitCore

enum ConnectionKind: String, CaseIterable { case bluetooth = "Bluetooth", adb = "USB / Wi-Fi" }
struct PendingBluetoothReply {
    let token: UUID
    let continuation: CheckedContinuation<[String: Any], Error>
    let timeout: Task<Void, Never>
}

extension ConduitModel {
    var hasTrustedBluetoothPhone: Bool {
        transport == .bluetooth && !bluetoothAddress.isEmpty && BluetoothTrust.token(for: bluetoothAddress) != nil
    }
    var waitingForBluetooth: Bool { transport == .bluetooth && autoReconnect && shouldReconnect && hasTrustedBluetoothPhone }
    func shareCompanionViaBluetooth() {
        guard let apk = resource("conduit-companion.zip") ?? resource("conduit-companion.apk") else { return }
        let app = URL(fileURLWithPath: "/System/Applications/Utilities/Bluetooth File Exchange.app")
        guard FileManager.default.fileExists(atPath: app.path) else { NSWorkspace.shared.activateFileViewerSelecting([apk]); return }
        NSWorkspace.shared.open([apk], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.log(L("Не удалось открыть передачу Bluetooth. APK доступен внутри сборки и отдельно в чате.")) } }
        }
    }
    func refreshBluetoothPhones() {
        bluetoothPhones = BluetoothChannel.pairedPhones()
        if bluetoothAddress.isEmpty, bluetoothPhones.count == 1 { bluetoothAddress = bluetoothPhones[0].id }
    }
    func sendBridge(_ event: [String: Any]) {
        if transport == .bluetooth { bluetooth?.sendJSON(event) } else { bridge?.sendJSON(event) }
    }
    func reportConnectionError(_ message: String, alert: Bool) {
        connectionError = L(message)
        status = L("Подключение не выполнено")
        ConnectionDiagnostics.record("connection.failed", message)
        log(message)
        if alert { showConnectionError = true }
    }
    func copyConnectionDiagnostics() {
        let text = ConnectionDiagnostics.report() + "\nStage: \(connectionStage)\nLast error: \(connectionError ?? "none")"
        let board = NSPasteboard.general
        board.clearContents(); board.setString(text, forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboardChange = board.changeCount
        log(L("Диагностика скопирована"))
    }
    func cancelConnection() async {
        connectionAttempt = nil; shouldReconnect = false
        UserDefaults.standard.set(false, forKey: "bluetoothConnectionWanted")
        await cleanup(); busy = false; connectionStage = ""; status = L("Подключение отменено")
        ConnectionDiagnostics.record("connection.cancelled")
    }
    func connectBluetooth(automatic: Bool = false) async {
        guard !busy else {
            if !automatic { reportConnectionError(L("Подключение уже выполняется. Подожди или нажми «Отменить»."), alert: true) }
            return
        }
        refreshBluetoothPhones()
        let savedToken = bluetoothAddress.isEmpty ? nil : BluetoothTrust.token(for: bluetoothAddress)
        let code = bluetoothCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = BluetoothPreflight.problem(permission: ConnectionDiagnostics.permission, poweredOn: ConnectionDiagnostics.poweredOn,
                selection: bluetoothAddress, knownDevices: bluetoothPhones.map(\.id), remembered: savedToken != nil, code: code) {
            if !automatic { reportConnectionError(L(problem), alert: true) }
            return
        }
        guard let phone = bluetoothPhones.first(where: { $0.id == bluetoothAddress }) else {
            if !automatic { reportConnectionError(L("Список устройств изменился. Выбери телефон снова."), alert: true) }
            return
        }
        let attempt = UUID(); connectionAttempt = attempt
        busy = true
        if !automatic { connectionError = nil; showConnectionError = false }
        connectionSeconds = 0; connectionStage = L("Подготовка")
        let clock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self, self.connectionAttempt == attempt, self.busy else { return }
                self.connectionSeconds += 1
            }
        }
        defer { clock.cancel(); if connectionAttempt == attempt { busy = false; connectionAttempt = nil } }
        shouldReconnect = true
        UserDefaults.standard.set(true, forKey: "bluetoothConnectionWanted")
        ConnectionDiagnostics.record("connection.begin", automatic ? "automatic" : "manual")
        await cleanup()
        guard connectionAttempt == attempt else { return }
        let id = UUID(); sessionID = id
        status = L("Соединяюсь по Bluetooth…"); bluetoothSetupError = nil; bluetoothAuthenticationFailed = false
        bluetoothDecoder = JSONLineDecoder()
        let channel = BluetoothChannel(); bluetooth = channel
        channel.onProgress = { [weak self] stage in
            guard let self, self.sessionID == id else { return }
            self.connectionStage = stage; self.status = stage
        }
        channel.onData = { [weak self] bytes in self?.receiveBluetooth(bytes, session: id) }
        channel.onClose = { [weak self] reason in
            guard let self, self.sessionID == id else { return }
            self.bluetoothSetupError = self.bluetoothSetupError ?? reason
            if !self.busy { self.bluetoothLost(reason) }
        }
        channel.authorizeServiceRefresh = { [weak self] in
            guard let self, self.sessionID == id else { return false }
            return self.reconnectPolicy.allowServiceRefresh(automatic: automatic, at: ProcessInfo.processInfo.systemUptime)
        }
        do {
            try await channel.connect(phone)
            guard sessionID == id, connectionAttempt == attempt else { return }
            connectionStage = savedToken == nil ? L("Проверяю код Conduit на телефоне…") : L("Восстанавливаю сохранённое соединение…"); status = connectionStage
            ConnectionDiagnostics.record("application.auth", savedToken == nil ? "new-pair" : "remembered-pair")
            channel.sendJSON(["type":"hello", "protocol":2, "client":BluetoothTrust.clientID,
                "name":Host.current().localizedName ?? "Mac", "token":savedToken ?? "", "code":code])
            for _ in 0..<100 {
                guard sessionID == id, connectionAttempt == attempt else { return }
                if companionReady || bluetoothSetupError != nil { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard companionReady else { throw AppError(bluetoothSetupError ?? L("Телефон открыл Bluetooth-канал, но Conduit не ответил за 10 секунд. Проверь, что на телефоне установлен APK 0.2.3 или новее и включено соединение.")) }
            connected = true; bluetoothCode = ""; connectionHeartbeat.reset(); reconnectPolicy.succeeded(); connectionError = nil
            UserDefaults.standard.set(phone.id, forKey: "lastBluetoothPhone")
            pasteboardChange = NSPasteboard.general.changeCount
            connectionStage = L("Готово"); status = "Bluetooth · " + phone.name
            sendBridge(["type":"preferences", "clipboard":clipboardEnabled])
            ConnectionDiagnostics.record("connection.ready")
            if autoDiagnostics { requestAndroidDiagnostics() }
            log(L("Bluetooth подключён. Уведомления и файлы готовы."))
        } catch {
            guard sessionID == id, connectionAttempt == attempt else { return }
            reconnectPolicy.failed(at: ProcessInfo.processInfo.systemUptime)
            if bluetoothAuthenticationFailed { shouldReconnect = false; UserDefaults.standard.set(false, forKey: "bluetoothConnectionWanted") }
            let failedStage = connectionStage
            await cleanup()
            connectionStage = failedStage
            reportConnectionError(error.localizedDescription, alert: !automatic)
        }
    }
    func forgetBluetoothPhone() async {
        await disconnect(); BluetoothTrust.forget(bluetoothAddress)
        status = L("Связь Conduit удалена. Получи новый код на телефоне.")
    }
    func bluetoothLost(_ reason: String) {
        guard !busy else { return }
        busy = true
        reconnectPolicy.failed(at: ProcessInfo.processInfo.systemUptime)
        Task {
            await cleanup(); connectionError = reason; ConnectionDiagnostics.record("connection.lost", reason); status = reason + L(". Ожидаю телефон…"); busy = false
        }
    }
    func receiveBluetooth(_ bytes: Data, session id: UUID) {
        guard sessionID == id else { return }
        do {
            for event in try bluetoothDecoder.append(bytes) {
                let type = event["type"] as? String ?? ""
                if !companionReady {
                    if type == "authError" { bluetoothAuthenticationFailed = true; ConnectionDiagnostics.record("application.auth.rejected"); bluetoothSetupError = L("Код не принят. На телефоне нажми «Связать новый Mac» и введи новый код."); continue }
                    guard type == "ready", event["protocol"] as? Int == 2 else { throw ProtocolError.malformed }
                    if let token = event["token"] as? String {
                        guard token.utf8.count == 64, token.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw ProtocolError.malformed }
                        try BluetoothTrust.save(token, for: bluetoothAddress)
                    }
                    companionReady = true; connected = true; connectionHeartbeat.reset()
                }
                connectionHeartbeat.acknowledge()
                if ["fileReady","fileAck","fileDone","fileInfo","fileData","fileError"].contains(type),
                   let key = event["id"] as? String, let pending = bluetoothReplies.removeValue(forKey: key) {
                    pending.timeout.cancel()
                    if type == "fileError" { pending.continuation.resume(throwing: AppError(event["message"] as? String ?? L("Ошибка передачи файла"))) }
                    else { pending.continuation.resume(returning: event) }
                    continue
                }
                switch type {
                case "ready", "status":
                    notificationAccess = event["notificationAccess"] as? Bool == true
                    notificationListenerConnected = event["notificationListenerConnected"] as? Bool ?? notificationAccess
                    bluetoothClipboardAuto = event["clipboardAuto"] as? Bool == true
                    bluetoothDeviceLocked = event["deviceLocked"] as? Bool == true
                    ConnectionDiagnostics.record("peer.state", "clipboardAuto=\(bluetoothClipboardAuto)")
                    companionStatus = notificationAccess ? L("Уведомления подключены по Bluetooth") : L("Разреши уведомления в Conduit на телефоне")
                case "pong":
                    if let locked = event["deviceLocked"] as? Bool { bluetoothDeviceLocked = locked }
                    ConnectionDiagnostics.record("heartbeat.pong")
                case "diagnostics":
                    do { try receiveAndroidDiagnostics(event) }
                    catch { androidDiagnosticsPending = false; androidDiagnosticsStatus = L("Не удалось сохранить журнал телефона"); ConnectionDiagnostics.record("android.diagnostics.invalid") }
                case "clipboard":
                    ConnectionDiagnostics.record("clipboard.from.phone")
                    if clipboardEnabled, connected, let text = event["text"] as? String, text.utf8.count <= ScrcpyDecoder.maxTextBytes {
                        let board = NSPasteboard.general
                        if board.string(forType: .string) != text {
                            board.clearContents()
                            guard board.setString(text, forType:.string) else { ConnectionDiagnostics.record("clipboard.mac.write.denied"); break }
                        }
                        pasteboardChange = board.changeCount
                        ConnectionDiagnostics.record("clipboard.applied.mac")
                        sendBridge(["type":"clipboardAck"])
                    } else {
                        ConnectionDiagnostics.record("clipboard.skipped.mac")
                    }
                case "notification":
                    if notificationsEnabled { Task { do { try await PhoneNotifications.show(event) } catch { log(L("Проверь разрешение уведомлений macOS")) } } }
                case "removed": if let key = event["key"] as? String { PhoneNotifications.remove(key) }
                case "file": Task { await receiveBluetoothFile(event) }
                case "result": if event["ok"] as? Bool == false { log(L(event["message"] as? String ?? L("Действие не выполнено"))) }
                default: break
                }
            }
        } catch {
            bluetoothSetupError = (error as? AppError)?.message ?? L("Ответ телефона не соответствует протоколу Conduit. Проверь версию Android-приложения.")
            ConnectionDiagnostics.record("application.response.invalid")
            bluetooth?.cancel()
            if !busy { bluetoothLost(L("Ошибка Bluetooth-канала")) }
        }
    }

    func bluetoothRequest(_ event: [String: Any]) async throws -> [String: Any] {
        guard transport == .bluetooth, connected, bluetooth != nil, let id = event["id"] as? String, bluetoothReplies[id] == nil else { throw AppError(L("Нет соединения с телефоном")) }
        let ticket = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, self.bluetoothReplies[id]?.token == ticket else { return }
                let pending = self.bluetoothReplies.removeValue(forKey: id)
                pending?.continuation.resume(throwing: AppError(L("Телефон не подтвердил передачу. Подключись и повтори.")))
            }
            bluetoothReplies[id] = PendingBluetoothReply(token: ticket, continuation: continuation, timeout: timeout)
            sendBridge(event)
        }
    }
    func sendBluetoothFiles(_ urls: [URL]) async {
        guard connected, !transferBusy else { return }
        transferBusy = true; defer { transferBusy = false; transferProgress = "" }
        for url in urls {
            let id = UUID().uuidString.lowercased()
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= BluetoothFilePolicy.maxSize else { throw AppError(L("По Bluetooth поддерживаются файлы до 100 МБ. Папку можно отправить ZIP.")) }
                transferProgress = L("Проверяю файл…")
                let hash = try await Task.detached { try BluetoothFilePolicy.sha256(url) }.value
                let reply = try await bluetoothRequest(["type":"fileBegin", "id":id, "name":FilePolicy.safeName(url.lastPathComponent), "size":size, "sha256":hash])
                guard reply["type"] as? String == "fileReady" else { throw ProtocolError.malformed }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                var offset = 0
                while let bytes = try file.read(upToCount: BluetoothFilePolicy.chunkSize), !bytes.isEmpty {
                    let ack = try await bluetoothRequest(["type":"fileChunk", "id":id, "offset":offset, "data":bytes.base64EncodedString()])
                    offset += bytes.count
                    guard ack["type"] as? String == "fileAck", ack["offset"] as? Int == offset else { throw ProtocolError.malformed }
                    transferProgress = "\(url.lastPathComponent) · \(size == 0 ? 100 : offset * 100 / size)%"
                }
                let done = try await bluetoothRequest(["type":"fileEnd", "id":id])
                guard done["type"] as? String == "fileDone" else { throw ProtocolError.malformed }
                log(L("Отправлен по Bluetooth: ") + url.lastPathComponent)
            } catch { sendBridge(["type":"fileAbort", "id":id]); log(error.localizedDescription) }
        }
    }
    func receiveBluetoothFile(_ event: [String: Any]) async {
        guard let path = event["path"] as? String, FilePolicy.allowedRemoteFile(path) else { return }
        let id = path.components(separatedBy: "/").last ?? ""
        guard BluetoothFilePolicy.validID(id) else { return }
        while receivingBluetoothFile && connected && transport == .bluetooth { try? await Task.sleep(nanoseconds: 200_000_000) }
        guard transport == .bluetooth, connected, !activeFiles.contains(id) else { return }
        if receivedFiles.contains(id) { sendBridge(["type":"fileReceived", "name":id]); return }
        receivingBluetoothFile = true; activeFiles.insert(id)
        defer { receivingBluetoothFile = false; activeFiles.remove(id) }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("conduit-bt-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stage) }
            let info = try await bluetoothRequest(["type":"fileGet", "id":id])
            guard info["type"] as? String == "fileInfo", let size = info["size"] as? Int,
                  let hash = info["sha256"] as? String else { throw ProtocolError.malformed }
            let receiver = try BluetoothFileReceiver(url: stage.appendingPathComponent("payload"), size: size, sha256: hash)
            while receiver.offset < size {
                let chunk = try await bluetoothRequest(["type":"fileRead", "id":id, "offset":receiver.offset])
                guard chunk["type"] as? String == "fileData", let offset = chunk["offset"] as? Int,
                      let base64 = chunk["data"] as? String, let bytes = Data(base64Encoded: base64) else { throw ProtocolError.malformed }
                try receiver.append(bytes, at: offset)
            }
            try receiver.finish()
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Conduit", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = FilePolicy.safeName(info["name"] as? String ?? event["name"] as? String ?? "file")
            try FileManager.default.moveItem(at: receiver.url, to: folder.appendingPathComponent(UUID().uuidString.prefix(8) + "_" + name))
            receivedFiles.append(id); if receivedFiles.count > 256 { receivedFiles.removeFirst(receivedFiles.count - 256) }
            UserDefaults.standard.set(receivedFiles, forKey: "receivedFiles")
            sendBridge(["type":"fileReceived", "name":id]); log(L("Получен по Bluetooth: ") + name)
        } catch { sendBridge(["type":"fileAbort", "id":id]); log(L("Файл не получен: ") + error.localizedDescription) }
    }
}
