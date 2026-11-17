import Foundation
import Security

@objc(ConduitPairingProtocol)
protocol PairingProtocol: NSObjectProtocol {
    @objc(read:interactive:reply:) func read(_ address: String, interactive: Bool, reply: @escaping (Int32, Data?) -> Void)
    @objc(save:address:reply:) func save(_ data: Data, address: String, reply: @escaping (Int32) -> Void)
    @objc(forget:reply:) func forget(_ address: String, reply: @escaping (Int32) -> Void)
}

enum BluetoothTrust {
    private static let service = "dev.conduit.bluetooth"
    static var clientID: String {
        if let id = UserDefaults.standard.string(forKey: "bluetoothClientID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "bluetoothClientID"); return id
    }
    // Looking up attributes never requests the pairing secret, including during SwiftUI redraws.
    static func contains(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        var query = base(address)
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static var serviceRequirement: String? {
        Bundle.main.object(forInfoDictionaryKey: "ConduitPairingRequirement") as? String
    }

    private static func withService(_ body: (PairingProtocol) -> Void) throws {
        guard let requirement = serviceRequirement else { throw accessError }
        let connection = NSXPCConnection(serviceName: "dev.conduit.mac.pairing")
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: PairingProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        var failed = false
        // NSXPC's forwarding proxy implements the interface dynamically.
        let remote: AnyObject = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in failed = true } as AnyObject
        body(unsafeBitCast(remote, to: PairingProtocol.self))
        if failed { throw accessError }
    }

    struct InteractionRequired: Error {}

    private static var accessError: AppError { AppError(L("Не удалось получить доступ к сохранённой связи в Связке ключей.")) }

    static func token(for address: String, interactive: Bool) throws -> String? {
        var result: OSStatus = errSecInternalComponent
        var data: Data?
        if serviceRequirement != nil {
            try withService { service in
                service.read(address, interactive: interactive) { result = $0; data = $1 }
            }
        } else {
            // SwiftPM and disposable ad-hoc builds have no signed XPC peer.
            var query = base(address)
            query[kSecReturnData as String] = true
            if !interactive { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
            var value: CFTypeRef?
            result = SecItemCopyMatching(query as CFDictionary, &value)
            data = value as? Data
        }
        if !interactive && result == errSecInteractionNotAllowed { throw InteractionRequired() }
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data, data.count == 64, let token = String(data: data, encoding: .utf8) else { throw accessError }
        return token
    }

    static func save(_ token: String, for address: String) throws {
        let data = Data(token.utf8)
        if serviceRequirement != nil {
            var status: OSStatus = errSecInternalComponent
            try withService { $0.save(data, address: address) { status = $0 } }
            guard status == errSecSuccess else { throw AppError(L("Не удалось сохранить связь в Связке ключей.")) }
            return
        }
        var query = base(address)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updated == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw AppError(L("Не удалось сохранить связь в Связке ключей.")) }
        } else if updated != errSecSuccess { throw AppError(L("Связка ключей не разрешила сохранить связь.")) }
    }
    static func forget(_ address: String) throws {
        var status: OSStatus = errSecInternalComponent
        if serviceRequirement != nil {
            try withService { $0.forget(address) { status = $0 } }
        } else { status = SecItemDelete(base(address) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw accessError }
    }
    private static func base(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: address]
    }
}
