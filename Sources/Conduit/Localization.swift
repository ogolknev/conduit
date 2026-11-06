import Foundation

/// The same catalogs supply SwiftUI labels, connection messages and notifications.
enum AppLocalization {
    static var previewLanguage: String?
    static func configure(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--language"), arguments.count > index + 1,
           ["en", "ru"].contains(arguments[index + 1]) { previewLanguage = arguments[index + 1] }
    }
    static func resolvedLanguage(_ selection: String? = nil) -> String {
        if let previewLanguage { return previewLanguage }
        let selected = selection ?? UserDefaults.standard.string(forKey: "language") ?? "system"
        if ["en", "ru"].contains(selected) { return selected }
        return Bundle.main.preferredLocalizations.first?.hasPrefix("ru") == true ? "ru" : "en"
    }
    static func validateBundle() -> Bool {
        let previous = previewLanguage; defer { previewLanguage = previous }
        var keys: Set<String>?
        for language in ["en", "ru"] {
            previewLanguage = language
            guard let url = bundle().url(forResource: "Localizable", withExtension: "strings"),
                  let data = try? Data(contentsOf: url),
                  let values = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String],
                  values.count >= 406 else { return false }
            let current = Set(values.keys)
            if let keys, keys != current { return false }; keys = current
            guard L("Устройства") == (language == "en" ? "Devices" : "Устройства"),
                  L("Подключено · %@", "Test") == (language == "en" ? "Connected · Test" : "Подключено · Test"),
                  L("%@ · %@ с", "Test", 3) == (language == "en" ? "Test · 3 s" : "Test · 3 с"),
                  L("Shizuku connected") == (language == "en" ? "Shizuku connected" : "Shizuku подключён") else { return false }
        }
        return true
    }
    static func bundle() -> Bundle {
        guard let path = Bundle.main.path(forResource: resolvedLanguage(), ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

func L(_ key: String, _ arguments: Any...) -> String {
    let value = AppLocalization.bundle().localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return value }
    return String(format: value, locale: Locale(identifier: AppLocalization.resolvedLanguage()), arguments: arguments.map { String(describing: $0) as CVarArg })
}

extension ConduitModel {
    func refreshLocalizedPresentation() {
        status = L(status); connectionStage = L(connectionStage)
        connectionError = connectionError.map { L($0) }
        companionStatus = L(companionStatus); androidDiagnosticsStatus = L(androidDiagnosticsStatus)
    }
}
