import Foundation

public enum BluetoothPermission: String { case unknown, allowed, denied, restricted }
public enum BluetoothPreflight {
    /// A manual connect action must always either begin or explain why it cannot.
    public static func problem(permission: BluetoothPermission, poweredOn: Bool?, selection: String, knownDevices: [String], remembered: Bool, code: String) -> String? {
        if permission == .denied || permission == .restricted {
            return "Conduit не разрешён доступ к Bluetooth. Открой Системные настройки → Конфиденциальность и безопасность → Bluetooth и включи Conduit."
        }
        if poweredOn == false { return "Bluetooth на Mac выключен. Включи его в настройках Bluetooth." }
        if selection.isEmpty { return "Не выбран телефон. Свяжи его с Mac в настройках Bluetooth, нажми «Обновить» и выбери в списке." }
        if !knownDevices.contains(selection) { return "Выбранного телефона больше нет в списке. Нажми «Обновить» и выбери его снова." }
        if !remembered {
            if code.isEmpty { return "Для первого подключения нужен код Conduit. На телефоне открой приложение, нажми «Связать новый Mac» и введи 8 цифр." }
            if code.count != 8 || !code.utf8.allSatisfy({ (48...57).contains($0) }) { return "Код Conduit должен содержать ровно 8 цифр. Это код из Android-приложения, а не код системного сопряжения Bluetooth." }
        }
        return nil
    }
}
