import Foundation
import CoreBluetooth

/// IOBluetooth can accept an operation before CoreBluetooth is ready, then never report it.
@MainActor final class BluetoothRadio: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothRadio()
    private var manager: CBCentralManager?
    func waitUntilReady() async throws {
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        for _ in 0..<100 {
            switch manager?.state {
            case .poweredOn: return
            case .poweredOff: throw AppError(L("Bluetooth на Mac выключен. Включи его в настройках Bluetooth."))
            case .unauthorized: throw AppError(L("Разреши Conduit доступ к Bluetooth в настройках конфиденциальности macOS."))
            case .unsupported: throw AppError(L("macOS не предоставила приложению Bluetooth-адаптер."))
            default: try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw AppError(L("Bluetooth-адаптер не подготовился за 10 секунд. Закрой и снова открой Conduit."))
    }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) { }
}
