import SwiftUI
import ConduitCore

struct NotificationInboxView: View {
    @ObservedObject var model: ConduitModel
    @State private var history = false

    var body: some View {
        let items = model.inbox.items.filter { history ? $0.state == .removed : $0.state == .active || $0.state == .failed }
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
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        InboxRow(model: model, item: item).id([item.id, item.instance])
                    }
                }
            }
        }.font(.system(size: 12))
            .environment(\.locale, Locale(identifier: AppLocalization.resolvedLanguage()))
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
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = item.icon, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    LineIcon("bell").padding(7).foregroundStyle(Palette.muted).background(Palette.soft)
                }
            }.frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.app).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 11)).fixedSize()
                    if dismissible {
                        Button { model.dismissNotification(item) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 22).background(Palette.soft, in: Circle())
                        }.buttonStyle(.plain).help(L("Удалить с телефона")).accessibilityLabel(L("Удалить с телефона"))
                    }
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
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
            .modifier(NotificationSwipe(enabled: dismissible, dismiss: { model.dismissNotification(item) }))
    }

    @ViewBuilder private var controls: some View {
        ForEach(item.actions ?? []) { action in
            let media = mediaLabel(action.id)
            let title = media?.title ?? action.label
            Button { model.performNotificationAction(action, on: item) } label: {
                if let media { Image(systemName: media.icon).frame(minWidth: 16) }
                else { Text(title) }
            }.buttonStyle(ActionStyle()).help(title).accessibilityLabel(title)
                .disabled(!model.canAct(on: item) || model.notificationActionRequest != nil)
        }
        if item.replyable {
            Button {
                composing.toggle()
                replyFocused = composing
            } label: { Label(L("Ответить"), systemImage: "arrowshape.turn.up.left") }
                .buttonStyle(ActionStyle()).disabled(!model.canAct(on: item))
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
