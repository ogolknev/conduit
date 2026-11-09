import AppKit
import UserNotifications
import ServiceManagement

@MainActor enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static func setEnabled(_ enabled: Bool) throws {
        let current = status
        if enabled && current != .enabled && current != .requiresApproval { try SMAppService.mainApp.register() }
        if !enabled && (current == .enabled || current == .requiresApproval) { try SMAppService.mainApp.unregister() }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    static var report: [String: Any] {
        ["loginItemStatus": status.rawValue, "loginItemEnabled": status == .enabled,
         "loginItemRequiresApproval": status == .requiresApproval]
    }
}

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
    func refreshLoginItemStatus() {
        launchAtLogin = LaunchAtLogin.status == .enabled || LaunchAtLogin.status == .requiresApproval
        loginItemNeedsApproval = LaunchAtLogin.status == .requiresApproval
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do { try LaunchAtLogin.setEnabled(enabled) }
        catch {
            loginItemError = L("Не удалось изменить автозапуск. Проверь объекты входа в настройках macOS.")
            ConnectionDiagnostics.record("login-item.failed", "code=\((error as NSError).code)")
        }
        refreshLoginItemStatus()
    }
    func refreshSystemPermissions() async {
        refreshLoginItemStatus()
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
