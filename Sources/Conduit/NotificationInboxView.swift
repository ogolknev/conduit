import SwiftUI
import ConduitCore

struct NotificationInboxView: View {
    @ObservedObject var model: ConduitModel
    @State private var history = false
    @Environment(\.calendar) private var calendar

    var body: some View {
        let items = model.inbox.items.filter { history ? $0.visibleInHistory : $0.visibleInActive }
        let pending = model.inbox.items.filter { $0.state == .pending }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 2) {
                    tab(L("Активные"), history: false)
                    tab(L("История"), history: true)
                }.padding(3).background(Palette.soft, in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                if history && !items.isEmpty {
                    Button(L("Очистить историю")) { model.clearNotificationHistory() }.buttonStyle(ActionStyle())
                }
            }
            if history {
                Text(L("Последние 500 уведомлений хранятся только на этом Mac.")).foregroundStyle(Palette.muted)
            }
            if !history && pending > 0 {
                Text(L("Ожидают удаления на телефоне · %@", pending)).foregroundStyle(Palette.muted)
            }
            if model.notificationSnapshot != nil { Text(L("Синхронизация уведомлений…")).foregroundStyle(Palette.muted) }
            if model.inboxStorageError { Text(L("Не удалось сохранить историю уведомлений.")).foregroundStyle(Palette.error) }
            if !model.companionReady {
                Text(L("Нет соединения. Удаление будет выполнено после подключения телефона.")).foregroundStyle(Palette.muted)
            } else if model.notificationSource == nil {
                Text(L("Обновите Conduit на телефоне для синхронизации уведомлений.")).foregroundStyle(Palette.warning)
            } else if !model.notificationListenerConnected {
                Text(L("Разреши доступ к уведомлениям на телефоне")).foregroundStyle(Palette.warning)
            }
            if model.notificationSyncError {
                HStack {
                    Text(L("Не удалось сверить уведомления с телефоном.")).foregroundStyle(Palette.warning)
                    Button(L("Повторить")) { model.notificationSynced = false; model.retryNotificationSnapshot() }
                }
            }
            if let result = model.inboxActionResult { Text(L(result)).foregroundStyle(Palette.muted) }
            if items.isEmpty {
                VStack(spacing: 12) {
                    LineIcon("bell").frame(width: 28, height: 28).foregroundStyle(Palette.muted)
                    Text(L("Нет уведомлений")).font(.system(size: 15, weight: .medium))
                }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
            } else {
                let dayFormatter = dayFormatter
                let days = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days.keys.sorted(by: >), id: \.self) { day in
                        let entries = days[day] ?? []
                        HStack(spacing: 12) {
                            Text(day, formatter: dayFormatter)
                                .font(.system(size: 13, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            Rectangle().fill(Palette.line).frame(height: 1)
                        }.padding(.top, 8).padding(.bottom, 10)
                        ForEach(entries) { item in
                            InboxRow(model: model, item: item)
                                .id([item.id, item.instance])
                                .background(Palette.soft)
                                .clipShape(DayRowShape(first: item.id == entries.first?.id, last: item.id == entries.last?.id))
                                .overlay(alignment: .bottom) {
                                    if item.id != entries.last?.id {
                                        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 70)
                                    }
                                }
                                .padding(.bottom, item.id == entries.last?.id ? 12 : 0)
                        }
                    }
                }
            }
        }.font(.system(size: 12))
            .environment(\.locale, Locale(identifier: AppLocalization.resolvedLanguage()))
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLocalization.resolvedLanguage())
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }

    private func tab(_ label: String, history value: Bool) -> some View {
        Button { history = value } label: {
            Text(label).font(.system(size: 13, weight: history == value ? .semibold : .medium))
                .padding(.horizontal, 16).padding(.vertical, 7)
                .foregroundStyle(history == value ? Palette.ink : Palette.muted)
                .background(history == value ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(history == value ? .isSelected : [])
    }
}

// macOS 13 has no UnevenRoundedRectangle. Round only the exposed ends of a day.
private struct DayRowShape: Shape {
    let first: Bool
    let last: Bool
    func path(in rect: CGRect) -> Path {
        let radius = min(12, rect.height / 2, rect.width / 2)
        var path = Path(roundedRect: rect, cornerRadius: radius)
        if !first { path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: radius)) }
        if !last { path.addRect(CGRect(x: rect.minX, y: rect.maxY - radius, width: rect.width, height: radius)) }
        return path
    }
}

private struct InboxRow: View {
    @ObservedObject var model: ConduitModel
    let item: InboxNotification
    @State private var reply = ""
    @State private var composing = false
    @FocusState private var replyFocused: Bool
    private var dismissible: Bool { item.dismissible && (item.state == .active || item.state == .failed) }
    private var canReply: Bool {
        model.canAct(on: item) && model.inboxReplyRequest == nil && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reply.utf16.count <= 4096
    }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let data = item.icon, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    if (item.actions ?? []).contains(where: { mediaLabel($0.id) != nil }) {
                        Image(systemName: "music.note").font(.system(size: 18, weight: .medium))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(Palette.canvas).background(Palette.accent)
                    } else {
                        Text(String(item.app.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(Palette.ink).background(Palette.surface)
                    }
                }
            }.frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.app).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.date, style: .time)
                        .font(.system(size: 11)).monospacedDigit().fixedSize()
                    Button { model.closeInboxNotification(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("Закрыть на Mac")).accessibilityLabel(L("Закрыть на Mac"))
                }.foregroundStyle(Palette.muted)
                if !item.title.isEmpty {
                    Text(item.title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                if !item.body.isEmpty {
                    Text(item.body).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.state == .failed { Text(L("Телефон не подтвердил удаление. Можно повторить.")).foregroundStyle(Palette.error) }
                if item.state == .active {
                    if !(item.actions ?? []).isEmpty || item.replyable {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { controls }
                            VStack(alignment: .leading, spacing: 6) { controls }
                        }.padding(.top, 6)
                    }
                    if composing && item.replyable {
                        HStack {
                            TextField(L("Сообщение"), text: $reply).textFieldStyle(.roundedBorder)
                                .focused($replyFocused).onSubmit { if canReply { sendReply() } }
                            Button(L("Отправить")) { sendReply() }.buttonStyle(ActionStyle()).disabled(!canReply)
                        }.padding(.top, 4)
                    }
                }
            }
        }.padding(.horizontal, 18).padding(.vertical, 15).background(Palette.soft)
            .modifier(NotificationSwipe { model.closeInboxNotification(item) })
            .contextMenu {
                Button(L("Закрыть на Mac")) { model.closeInboxNotification(item) }
                if dismissible {
                    Button(L("Удалить с телефона")) { model.dismissNotification(item) }
                }
            }
    }

    @ViewBuilder private var controls: some View {
        ForEach(item.actions ?? []) { action in
            let media = mediaLabel(action.id)
            let title = media?.title ?? action.label
            Button { model.performNotificationAction(action, on: item) } label: {
                if let media { Image(systemName: media.icon).frame(minWidth: 16) }
                else { Text(title) }
            }.buttonStyle(InboxActionStyle(primary: action.id == "pause" || action.id == "play")).help(title).accessibilityLabel(title)
                .disabled(!model.canAct(on: item) || model.notificationActionRequest != nil)
        }
        if item.replyable {
            Button {
                composing.toggle()
                replyFocused = composing
            } label: { Label(L("Ответить"), systemImage: "arrowshape.turn.up.left") }
                .buttonStyle(InboxActionStyle()).disabled(!model.canAct(on: item))
        }
    }
    private func mediaLabel(_ id: String) -> (title: String, icon: String)? {
        switch id {
        case "previous": return (L("Предыдущий трек"), "backward.end.fill")
        case "play": return (L("Воспроизвести"), "play.fill")
        case "pause": return (L("Пауза"), "pause.fill")
        case "next": return (L("Следующий трек"), "forward.end.fill")
        default: return nil
        }
    }
    private func sendReply() { model.replyToNotification(item, text: reply) }
}


private struct InboxActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11).frame(minHeight: 28)
            .foregroundStyle(primary ? Palette.canvas : Palette.ink)
            .background(primary ? Palette.accent : Palette.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(primary ? .clear : Palette.line) }
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
            .contentShape(Capsule())
    }
}
