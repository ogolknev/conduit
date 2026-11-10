import SwiftUI
import ConduitCore

struct NotificationInboxView: View {
    @ObservedObject var model: ConduitModel
    @State private var history = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Picker(L("Уведомления"), selection: $history) {
                    Text(L("Активные")).tag(false)
                    Text(L("История")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 250)
                Spacer()
                if history {
                    Button(L("Очистить историю")) { model.clearNotificationHistory() }
                        .disabled(!model.inbox.items.contains { $0.state == .removed })
                }
            }
            Text(L("Последние 500 уведомлений хранятся только на этом Mac.")).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.notificationSnapshot != nil { Text(L("Синхронизация уведомлений…")).font(.system(size: 12)).foregroundStyle(.secondary) }
            if model.inboxStorageError { Text(L("Не удалось сохранить историю уведомлений.")).foregroundStyle(Palette.error) }
            if !model.companionReady {
                Text(L("Нет соединения. Удаление будет выполнено после подключения телефона.")).font(.system(size: 13)).foregroundStyle(.secondary)
            } else if model.notificationSource == nil {
                Text(L("Обновите Conduit на телефоне для синхронизации уведомлений.")).foregroundStyle(Palette.warning)
            } else if !model.notificationListenerConnected {
                Text(L("Разреши доступ к уведомлениям на телефоне")).foregroundStyle(Palette.warning)
            }
            if model.notificationSyncError {
                HStack {
                    Text(L("Не удалось сверить уведомления с телефоном.")).foregroundStyle(Palette.warning)
                    Button(L("Повторить")) { model.notificationSynced = false; model.sendBridge(["type": "ping"]); model.retryNotificationSnapshot() }
                }
            }
            if let result = model.inboxActionResult { Text(L(result)).font(.system(size: 12)).foregroundStyle(.secondary) }
            let items = model.inbox.items.filter { history ? $0.state == .removed : $0.state != .removed }
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(L("Нет уведомлений")).font(.system(size: 16, weight: .medium))
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            LazyVStack(spacing: 12) {
                ForEach(items) { item in InboxRow(model: model, item: item) }
            }
        }
    }
}

private struct InboxRow: View {
    @ObservedObject var model: ConduitModel
    let item: InboxNotification
    @State private var reply = ""
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.body).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if item.state == .pending { Text(L("Ожидает удаления на телефоне")).foregroundStyle(Palette.warning) }
                if item.state == .failed { Text(L("Телефон не подтвердил удаление. Можно повторить.")).foregroundStyle(Palette.error) }
                if item.state != .removed {
                    HStack {
                        Button(L("Удалить с телефона")) { model.dismissNotification(item) }
                            .disabled(!item.dismissible || item.state == .pending)
                        if !item.dismissible { Text(L("Это уведомление нельзя удалить")).foregroundStyle(.secondary) }
                    }
                    if item.replyable {
                        HStack {
                            TextField(L("Сообщение"), text: $reply)
                            Button(L("Ответить")) { model.replyToNotification(item, text: reply) }
                                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reply.utf16.count > 4096 || !model.companionReady || !model.notificationSynced || model.notificationSource != item.source || item.state != .active || model.inboxReplyRequest != nil)
                        }
                    }
                }
            }.padding(.top, 14)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let data = item.icon, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                } else { Image(systemName: "bell").frame(width: 32, height: 32).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.app).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.date, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(item.date, style: .time).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    if item.state == .pending { Text(L("Ожидает удаления на телефоне")).font(.system(size: 12)).foregroundStyle(Palette.warning) }
                    if item.state == .failed { Text(L("Не удалось удалить")).font(.system(size: 12)).foregroundStyle(Palette.error) }
                }
            }
        }.environment(\.locale, Locale(identifier: AppLocalization.resolvedLanguage())).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
}
