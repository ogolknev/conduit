import Foundation
import ConduitCore

extension ConduitModel {
    func requestAndroidDiagnostics() {
        guard connected, companionReady, transport == .bluetooth, !androidDiagnosticsPending else { return }
        androidDiagnosticsPending = true; androidDiagnosticsStatus = L("Запрашиваю журнал телефона…")
        let request = UUID(); androidDiagnosticsRequest = request
        sendBridge(["type":"diagnosticsRequest"])
        ConnectionDiagnostics.record("android.diagnostics.request")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, self.androidDiagnosticsRequest == request, self.androidDiagnosticsPending else { return }
            self.androidDiagnosticsPending = false
            self.androidDiagnosticsStatus = L("Телефон не ответил. Для журнала нужен APK 0.2.6 или новее.")
            ConnectionDiagnostics.record("android.diagnostics.timeout")
        }
    }
    func receiveAndroidDiagnostics(_ event: [String: Any]) throws {
        guard let report = event["report"] as? String else { throw ProtocolError.malformed }
        try AndroidDiagnosticArchive.save(report, in: ConnectionDiagnostics.androidDirectory)
        androidDiagnosticsPending = false; androidDiagnosticsRequest = UUID()
        androidDiagnosticsStatus = L("Журнал телефона обновлён · ") + Date().formatted(date:.omitted,time:.standard)
        ConnectionDiagnostics.record("android.diagnostics.saved")
        let combined = ConnectionDiagnostics.androidDirectory.appendingPathComponent("combined-latest.txt")
        try Data(ConnectionDiagnostics.report().utf8).write(to:combined,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:combined.path)
    }
}
