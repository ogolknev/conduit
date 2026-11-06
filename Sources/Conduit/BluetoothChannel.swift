import Foundation
import IOBluetooth
import Security
import ConduitCore

struct BluetoothPhone: Identifiable {
    let id: String
    let name: String
    let device: IOBluetoothDevice
}

// Retain legacy Objective-C callback objects until they are consumed on the main queue.
private struct BluetoothCallbackReference<T: AnyObject>: @unchecked Sendable { let value: T? }

@MainActor final class BluetoothChannel: NSObject, IOBluetoothRFCOMMChannelDelegate, IOBluetoothDeviceAsyncCallbacks {
    static let serviceID = "831E2350-1D98-4ED9-8BD1-65CDA12A5AD0"
    var onData: ((Data) -> Void)?
    var onClose: ((String) -> Void)?
    var onProgress: ((String) -> Void)?
    private var channel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var pending: CheckedContinuation<Void, Error>?
    private var outbound = Data()
    private var inFlight: NSMutableData?
    private var closed = false
    private var phase = "idle"
    private var deadline: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?
    private var mayRefreshServices = true
    private var refreshedServices = false
    private var requestedChannel: BluetoothRFCOMMChannelID = 0
    private var linkAttempts = 0

    static func pairedPhones() -> [BluetoothPhone] {
        var seen = Set<String>()
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap {
            guard let address = $0.addressString else { return nil }
            guard seen.insert(address.lowercased()).inserted else { return nil }
            return BluetoothPhone(id: address, name: $0.name ?? address, device: $0)
        }.sorted { $0.name < $1.name }
    }
    private static func serviceUUID() -> IOBluetoothSDPUUID {
        var value = UUID(uuidString: serviceID)!.uuid
        return withUnsafeBytes(of: &value) { IOBluetoothSDPUUID(bytes: $0.baseAddress!, length: 16) }
    }
    func connect(_ phone: BluetoothPhone, allowServiceRefresh: Bool = true) async throws {
        guard !closed else { throw AppError(L("Попытка подключения уже закрыта. Нажми «Подключить» снова.")) }
        onProgress?(L("Подготавливаю Bluetooth…")); ConnectionDiagnostics.record("bluetooth.prepare")
        try await BluetoothRadio.shared.waitUntilReady()
        guard !closed else { throw AppError(L("Подключение отменено")) }
        mayRefreshServices = allowServiceRefresh
        device = phone.device
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            if phone.device.isConnected() { search() } else { connectDevice() }
        }
    }
    private func step(_ id: String, _ label: String, timeout: UInt64, failure: String) {
        phase = id; onProgress?(label); ConnectionDiagnostics.record(id)
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeout * 1_000_000_000) } catch { return }
            guard let self, !self.closed, self.pending != nil, self.phase == id else { return }
            if id == "rfcomm.open" { self.recoverOrFinish(failure) } else { self.finish(failure) }
        }
    }
    private func connectDevice() {
        guard let device, !closed, pending != nil else { return }
        linkAttempts = 0
        step("device.connect", L("Соединяю Mac с телефоном…"), timeout: 25,
             failure: L("Телефон не ответил на Bluetooth-подключение. Разблокируй его и открой Conduit."))
        requestDeviceConnection(device)
    }
    private func requestDeviceConnection(_ device: IOBluetoothDevice) {
        guard !closed, phase == "device.connect" else { return }
        linkAttempts += 1
        let result = device.openConnection(self)
        if result != kIOReturnSuccess { ConnectionDiagnostics.record("device.connect.start", Self.code(result)); finish(L("macOS не смогла подключиться к телефону по Bluetooth.")) }
    }
    private func recoverOrFinish(_ reason: String) {
        guard !closed else { return }
        guard mayRefreshServices, !refreshedServices, let device, device.isPaired() else { finish(reason); return }
        refreshedServices = true
        step("device.refresh", L("Переподключаю телефон для обновления служб…"), timeout: 6,
             failure: L("macOS не смогла обновить список служб. В настройках Bluetooth отключи телефон и подключи снова, затем повтори попытку в Conduit."))
        // This selected device only, once for a manual attempt. Never toggle the adapter.
        let previous = channel; channel = nil; previous?.setDelegate(nil); previous?.close()
        if device.isConnected() {
            let result = device.closeConnection()
            guard result == kIOReturnSuccess else { ConnectionDiagnostics.record("device.refresh.close", Self.code(result)); finish(reason); return }
        }
        linkTask = Task { [weak self] in
            for _ in 0..<50 {
                guard let self, !self.closed, self.phase == "device.refresh" else { return }
                if !device.isConnected() { self.connectDevice(); return }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
        }
    }
    private func search() {
        guard let device, !closed else { return }
        // macOS 26 answers from its stored service table; a missing entry is refreshed by relinking.
        step("sdp.full", L("Ищу Conduit на телефоне…"), timeout: 20,
             failure: L("Телефон не ответил на поиск Conduit за 20 секунд. Открой Conduit на телефоне, включи Bluetooth-соединение и проверь системное сопряжение."))
        let result = device.performSDPQuery(self)
        if result != kIOReturnSuccess {
            ConnectionDiagnostics.record("sdp.start", Self.code(result))
            finish(L("macOS не смогла начать поиск Conduit на телефоне. Проверь Bluetooth и доступ Conduit в настройках конфиденциальности."))
        }
    }
    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let callback = BluetoothCallbackReference(value: device)
        DispatchQueue.main.async { [weak self] in self?.handleSDP(callback.value, status: status) }
    }
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) { }
    nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let callback = BluetoothCallbackReference(value: device)
        DispatchQueue.main.async { [weak self] in self?.handleDeviceConnection(callback.value, status: status) }
    }
    private func handleDeviceConnection(_ connectedDevice: IOBluetoothDevice?, status: IOReturn) {
        guard !closed, phase == "device.connect", pending != nil else { return }
        ConnectionDiagnostics.record("device.connection", Self.code(status))
        if let connectedDevice { device = connectedDevice }
        guard status == kIOReturnSuccess, let device, device.isPaired() else { finish(L("Не удалось подтвердить Bluetooth-соединение с сопряжённым телефоном.")); return }
        if device.isConnected() { search(); return }
        // An early command on macOS 26 can be discarded with status zero. Do not call that success.
        guard linkAttempts < 4 else { finish(L("macOS не установила соединение с телефоном. Повтори подключение в настройках Bluetooth.")); return }
        linkTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            self?.requestDeviceConnection(device)
        }
    }
    private func handleSDP(_ callbackDevice: IOBluetoothDevice?, status: IOReturn) {
        guard !closed, pending != nil, phase.hasPrefix("sdp.") else { return }
        if let callbackDevice { device = callbackDevice }
        ConnectionDiagnostics.record("sdp.callback", Self.code(status))
        guard status == kIOReturnSuccess else { finish(L("Телефон не ответил на поиск службы Conduit. Разблокируй его, открой Conduit и включи Bluetooth-соединение.")); return }
        ConnectionDiagnostics.record("sdp.services", "count=\(device?.services?.count ?? 0)")
        guard let record = device?.getServiceRecord(for: Self.serviceUUID()) else {
            recoverOrFinish(L("Служба Conduit не найдена после поиска. На телефоне открой Conduit 0.2.3 или новее и включи Bluetooth-соединение. При автоматическом подключении нажми «Подключить» вручную, чтобы обновить список служб.")); return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        let lookup = record.getRFCOMMChannelID(&channelID)
        guard lookup == kIOReturnSuccess, channelID > 0, let device else {
            ConnectionDiagnostics.record("rfcomm.lookup", Self.code(lookup)); finish(L("Телефон сообщил службу Conduit без канала подключения. Выключи и снова включи соединение в Android-приложении.")); return
        }
        requestedChannel = channelID
        step("rfcomm.open", L("Открываю Bluetooth-канал…"), timeout: 15, failure: L("Bluetooth-канал не открылся за 15 секунд. Перезапусти Bluetooth-соединение в Conduit на телефоне."))
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        if result != kIOReturnSuccess { ConnectionDiagnostics.record("rfcomm.start", Self.code(result)); recoverOrFinish(L("macOS не смогла открыть Bluetooth-канал. Проверь системное сопряжение и запущен ли Conduit на телефоне.")) }
    }
    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        let callback = BluetoothCallbackReference(value: rfcommChannel)
        DispatchQueue.main.async { [weak self] in self?.handleOpen(callback.value, status: error) }
    }
    private func handleOpen(_ opened: IOBluetoothRFCOMMChannel?, status error: IOReturn) {
        guard !closed, phase == "rfcomm.open" else { return }
        ConnectionDiagnostics.record("rfcomm.callback", Self.code(error))
        guard error == kIOReturnSuccess, let opened, opened.isOpen() else { recoverOrFinish(L("Телефон отклонил Bluetooth-канал Conduit. Открой Android-приложение и включи соединение снова.")); return }
        guard opened.getID() == requestedChannel else { opened.setDelegate(nil); opened.close(); finish(L("macOS вернула другой Bluetooth-канал. Повтори подключение.")); return }
        channel = opened
        guard let device, device.isPaired() else { finish(L("Не завершено системное сопряжение. Свяжи телефон и Mac в настройках Bluetooth.")); return }
        step("rfcomm.authentication", L("Проверяю защищённое соединение…"), timeout: 8, failure: L("Телефон не подтвердил аутентификацию Bluetooth-соединения."))
        // getEncryptionMode() on macOS 26.6.2 is literally `mov w0, #0; ret`.
        // Authenticate the live paired link instead. Android's secure RFCOMM listener
        // requires authentication AND encryption; the one-time code/token follows this check.
        let peer = BluetoothCallbackReference(value: device)
        let authentication = Task.detached { peer.value?.requestAuthentication() ?? kIOReturnError }
        linkTask = Task { [weak self] in
            let result = await authentication.value
            guard let self, !self.closed, self.phase == "rfcomm.authentication", self.channel === opened else { return }
            ConnectionDiagnostics.record("rfcomm.authentication.result", Self.code(result))
            guard result == kIOReturnSuccess, device.isPaired(), opened.isOpen() else { self.finish(L("Аутентификация Bluetooth-соединения не прошла. Повтори системное сопряжение телефона и Mac.")); return }
            self.phase = "connected"; self.deadline?.cancel()
            self.pending?.resume(); self.pending = nil; self.pump()
        }
    }
    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard dataLength > 0, dataLength <= 1_048_576 else { return }
        let bytes = Data(bytes: dataPointer, count: dataLength)
        let callback = BluetoothCallbackReference(value: rfcommChannel)
        DispatchQueue.main.async { [weak self] in guard let self, !self.closed, self.channel === callback.value else { return }; self.onData?(bytes) }
    }
    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let callback = BluetoothCallbackReference(value: rfcommChannel)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.channel != nil, self.channel === callback.value else { return }
            self.finish(L("Телефон закрыл Bluetooth-соединение. Проверь, что Conduit на телефоне запущен."))
        }
    }
    nonisolated func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.inFlight = nil
            guard error == kIOReturnSuccess else { ConnectionDiagnostics.record("rfcomm.write", Self.code(error)); self.finish(L("Не удалось передать данные по Bluetooth")); return }
            self.pump()
        }
    }
    func sendJSON(_ object: [String: Any]) {
        guard !closed else { return }
        guard var bytes = try? JSONSerialization.data(withJSONObject: object), bytes.count < JSONLineDecoder.maxLine else { finish(L("Сообщение слишком велико для Bluetooth-канала")); return }
        bytes.append(10)
        guard outbound.count + bytes.count <= 2_097_152 else { finish(L("Bluetooth-очередь переполнена. Подключись снова.")); return }
        outbound.append(bytes); pump()
    }
    private func pump() {
        guard !closed, pending == nil, inFlight == nil, let channel, !outbound.isEmpty else { return }
        let mtu = Int(channel.getMTU())
        guard mtu > 0 else { finish(L("macOS не сообщила размер пакета Bluetooth. Переподключи телефон.")); return }
        let count = min(outbound.count, min(mtu, 65535))
        let packet = NSMutableData(data: outbound.prefix(count)); inFlight = packet; outbound.removeFirst(count)
        let result = channel.writeAsync(packet.mutableBytes, length: UInt16(count), refcon: nil)
        if result != kIOReturnSuccess { ConnectionDiagnostics.record("rfcomm.write.start", Self.code(result)); inFlight = nil; finish(L("Ошибка отправки по Bluetooth")) }
    }
    func cancel() { finish(L("Подключение отменено"), notify: false) }
    nonisolated private static func code(_ value: IOReturn) -> String { String(format: "native=0x%08X", UInt32(bitPattern: value)) }
    private func finish(_ reason: String, notify: Bool = true) {
        guard !closed else { return }
        closed = true; deadline?.cancel(); deadline = nil; linkTask?.cancel(); linkTask = nil
        ConnectionDiagnostics.record(notify ? "channel.failed" : "channel.cancelled", reason)
        pending?.resume(throwing: AppError(reason)); pending = nil
        channel?.setDelegate(nil); channel?.close(); channel = nil
        outbound.removeAll(); inFlight = nil
        if notify { onClose?(reason) }
        onData = nil; onClose = nil; onProgress = nil
    }
}

enum BluetoothTrust {
    private static let service = "dev.conduit.bluetooth"
    static var clientID: String {
        if let id = UserDefaults.standard.string(forKey: "bluetoothClientID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "bluetoothClientID"); return id
    }
    static func token(for address: String) -> String? {
        var query = base(address); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, for address: String) throws {
        var query = base(address)
        let data = Data(token.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updated == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AppError(L("Не удалось сохранить связь в Связке ключей.")) }
        } else if updated != errSecSuccess { throw AppError(L("Связка ключей не разрешила сохранить связь.")) }
    }
    static func forget(_ address: String) { SecItemDelete(base(address) as CFDictionary) }
    private static func base(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address]
    }
}
