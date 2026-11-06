import Testing
@testable import ConduitCore

struct ConnectionPreflightTests {
    @Test func staleSelectionExplainsHowToRecover() {
        let error = BluetoothPreflight.problem(permission: .allowed, poweredOn: true, selection: "old", knownDevices: ["phone"], remembered: false, code: "12345678")
        #expect(error?.contains("Обновить") == true)
    }
    @Test func deniedPermissionWinsOverEmptyDeviceList() {
        let error = BluetoothPreflight.problem(permission: .denied, poweredOn: nil, selection: "", knownDevices: [], remembered: false, code: "")
        #expect(error?.contains("Конфиденциальность") == true)
    }
    @Test func explainsMissingCodeAndRejectsSystemPairingCode() {
        for code in ["", "123456", "１２３４５６７８"] {
            #expect(BluetoothPreflight.problem(permission: .allowed, poweredOn: true, selection: "phone", knownDevices: ["phone"], remembered: false, code: code) != nil)
        }
    }
    @Test func rememberedPeerDoesNotNeedAnotherCode() {
        #expect(BluetoothPreflight.problem(permission: .allowed, poweredOn: true, selection: "phone", knownDevices: ["phone"], remembered: true, code: "") == nil)
    }
    @Test func validNewPairAndRadioOffHaveDifferentOutcomes() {
        #expect(BluetoothPreflight.problem(permission: .allowed, poweredOn: true, selection: "phone", knownDevices: ["phone"], remembered: false, code: "12345678") == nil)
        #expect(BluetoothPreflight.problem(permission: .allowed, poweredOn: false, selection: "phone", knownDevices: ["phone"], remembered: false, code: "12345678")?.contains("выключен") == true)
    }
}
