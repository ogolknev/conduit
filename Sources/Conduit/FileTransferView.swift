import SwiftUI
import ConduitCore

struct FileTransferList: View {
    let transfers: [FileTransfer]
    var body: some View {
        if transfers.contains(where: { $0.phase.isActive }) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in rows(now: ProcessInfo.processInfo.systemUptime) }
        } else { rows(now: ProcessInfo.processInfo.systemUptime) }
    }
    private func rows(now: TimeInterval) -> some View {
        VStack(spacing: 8) {
            ForEach(transfers.filter { $0.phase.isActive } + transfers.filter { !$0.phase.isActive }) { item in
                HStack(alignment: .top, spacing: 12) {
                    LineIcon(item.direction == .sending ? "upload" : "download").frame(width: 22, height: 24).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text(title(item, now: now)).font(.system(size: 12)).foregroundStyle(color(item))
                        }
                        HStack {
                            Text((item.direction == .sending ? L("На телефон") : L("С телефона")) + " · " + item.transport)
                            Spacer()
                            if let fraction = item.fraction { Text("\(Int(fraction * 100))%").monospacedDigit() }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                        if item.phase.isActive {
                            if let fraction = item.fraction { ProgressView(value: fraction).tint(Palette.accent) }
                            else { ProgressView().progressViewStyle(.linear).tint(Palette.accent) }
                        }
                        HStack {
                            Text(byteDetails(item))
                            Spacer()
                            if let rate = item.bytesPerSecond(at: now), item.phase != .failed {
                                Text(bytes(Int64(rate)) + L("/с"))
                            }
                            if item.startedAt != nil { Text(duration(item.elapsed(at: now))).monospacedDigit() }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                        if let error = item.error { Text(error).font(.system(size: 12)).foregroundStyle(Palette.error).textSelection(.enabled) }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file; formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func byteDetails(_ item: FileTransfer) -> String {
        if let current = item.transferredBytes, let total = item.totalBytes { return bytes(current) + " / " + bytes(total) }
        if let total = item.totalBytes { return bytes(total) }
        if let current = item.transferredBytes, current > 0 { return bytes(current) }
        return L("Размер неизвестен")
    }
    private func title(_ item: FileTransfer, now: TimeInterval) -> String {
        switch item.phase {
        case .preparing: return L("Подготовка файла…")
        case .waiting: return L("Ожидание передачи")
        case .transferring: return item.isStalled(at: now) ? L("Ожидаю данные…") : L("Передача…")
        case .verifying: return L("Проверка и сохранение…")
        case .completed: return item.direction == .sending ? L("Отправлено") : L("Получено")
        case .failed: return L("Передача не завершена")
        }
    }
    private func color(_ item: FileTransfer) -> Color {
        item.phase == .failed ? Palette.error : item.phase == .completed ? Palette.success : Palette.muted
    }
}
