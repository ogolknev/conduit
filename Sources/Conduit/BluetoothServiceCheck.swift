import Foundation
import IOBluetooth

/// A diagnostic SDP lookup only: never opens RFCOMM, sends a pairing code or touches a clipboard.
@MainActor final class BluetoothServiceCheck: NSObject, IOBluetoothDeviceAsyncCallbacks {
    private(set) var result: [String: Any]?
    /// Exercises the production transport, then closes it before any application handshake or payload.
    static func checkLink(address: String) -> [String: Any] {
        guard let device = IOBluetoothDevice(addressString: address), device.isPaired() else { return ["status":"not-paired"] }
        let channel = BluetoothChannel()
        var result: [String: Any]?
        let task = Task { @MainActor in
            do {
                try await channel.connect(BluetoothPhone(id:address, name:"phone", device:device), allowServiceRefresh:false)
                result = ["status":"authenticated-rfcomm", "applicationDataSent":false]
            } catch { result = ["status":"link-failed", "error":error.localizedDescription] }
            channel.cancel()
        }
        let deadline = Date().addingTimeInterval(55)
        while result == nil && Date() < deadline { RunLoop.main.run(until:min(Date().addingTimeInterval(0.05),deadline)) }
        task.cancel(); channel.cancel()
        return result ?? ["status":"link-timeout"]
    }
    static func run(address: String) -> [String: Any] {
        guard let device = IOBluetoothDevice(addressString: address) else { return ["status":"invalid-address"] }
        let probe = BluetoothServiceCheck()
        let started = device.performSDPQuery(probe)
        guard started == kIOReturnSuccess else { return ["status":"sdp-start-failed", "native":String(format:"0x%08X", UInt32(bitPattern:started))] }
        let deadline = Date().addingTimeInterval(20)
        while probe.result == nil && Date() < deadline {
            RunLoop.main.run(until: min(Date().addingTimeInterval(0.05), deadline))
        }
        return probe.result ?? ["status":"sdp-timeout"]
    }
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) { }
    nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) { }
    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let callback = ServiceCheckReference(value: device)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard status == kIOReturnSuccess, let device = callback.value else {
                self.result = ["status":"sdp-failed", "native":String(format:"0x%08X", UInt32(bitPattern:status))]; return
            }
            var value = UUID(uuidString: BluetoothChannel.serviceID)!.uuid
            let uuid = withUnsafeBytes(of: &value) { IOBluetoothSDPUUID(bytes:$0.baseAddress!, length:16) }
            let record = device.getServiceRecord(for: uuid)
            var channel: BluetoothRFCOMMChannelID = 0
            let lookup = record?.getRFCOMMChannelID(&channel)
            self.result = ["status":"sdp-complete", "conduitService":record != nil,
                "rfcommAvailable":lookup == kIOReturnSuccess && channel > 0, "serviceCount":device.services?.count ?? 0,
                "catalogMayBeCached":true, "namedConduit":(device.services as? [IOBluetoothSDPServiceRecord] ?? []).contains { $0.getServiceName()?.localizedCaseInsensitiveContains("Conduit") == true }]
        }
    }
}
private struct ServiceCheckReference<T: AnyObject>: @unchecked Sendable { let value: T? }
