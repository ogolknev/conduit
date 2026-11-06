import AppKit
import UserNotifications

enum MacNotificationPermission {
    case checking, notAsked, denied, allowed, quiet, unknown
    var title: String {
        switch self {
        case .checking: return L("Проверка…")
        case .notAsked: return L("Доступ не запрошен")
        case .denied: return L("Отключены в macOS")
        case .allowed: return L("Разрешены")
        case .quiet: return L("Разрешены без баннеров")
        case .unknown: return L("Состояние неизвестно")
        }
    }
    var allowsDelivery: Bool { self == .allowed || self == .quiet }
    var actionTitle: String { self == .notAsked ? L("Разрешить") : L("Настройки") }
}

extension ConduitModel {
    func refreshSystemPermissions() async {
        macBluetoothPermission = ConnectionDiagnostics.permission
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: macNotificationPermission = .notAsked
        case .denied: macNotificationPermission = .denied
        case .authorized: macNotificationPermission = settings.alertSetting == .enabled ? .allowed : .quiet
        case .provisional: macNotificationPermission = .quiet
        @unknown default: macNotificationPermission = .unknown
        }
    }
    func openMacNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.conduit.mac")!)
    }
}
