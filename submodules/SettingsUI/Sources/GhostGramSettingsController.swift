import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct GhostGramEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let option: GhostGramOption?
    let value: Bool
    let isLink: Bool

    static func < (lhs: GhostGramEntry, rhs: GhostGramEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let option = self.option {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title, value: self.value, sectionId: self.section, style: .blocks, updated: { value in
                GhostGramSettings.shared.set(option, value: value)
            })
        } else if self.isLink {
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if let url = URL(string: "https://t.me/rayzen_ezz") {
                    UIApplication.shared.open(url)
                }
            })
        } else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        }
    }
}

public func ghostGramSettingsController(context: AccountContext) -> ViewController {
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, GhostGramSettings.shared.signal)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = GhostGramSettings.shared
        var entries: [GhostGramEntry] = []
        func text(_ section: Int32, _ title: String, link: Bool = false) {
            entries.append(GhostGramEntry(stableId: Int32(entries.count), section: section, title: title, option: nil, value: false, isLink: link))
        }
        func toggle(_ section: Int32, _ title: String, _ option: GhostGramOption) {
            entries.append(GhostGramEntry(stableId: Int32(entries.count), section: section, title: title, option: option, value: settings.value(option), isLink: false))
        }
        text(0, "GhostGram\nTelegram с настройками приватности.")
        toggle(1, "Режим призрака", .enabled)
        text(1, "Общий переключатель. Настройки ниже сохраняются при выключении режима. Действует в этом приложении; другие клиенты Telegram могут раскрывать вашу активность.")
        toggle(2, "Не читать сообщения", .hideRead)
        text(2, "Не отправлять собеседнику отметку о прочтении при открытии чата.")
        toggle(3, "Не читать истории", .hideStoryRead)
        text(3, "Не отправлять отметку о просмотре истории.")
        toggle(4, "Не отправлять «онлайн»", .hideOnline)
        text(4, "Не сообщать о присутствии при открытии приложения. Отправка сообщений и разрешённые отметки о прочтении могут раскрывать активность на сервере.")
        toggle(5, "Не отправлять «печатает»", .hideTyping)
        text(5, "Скрывать набор текста, запись голоса и другие индикаторы действий в чате.")
        toggle(6, "Автоматический «офлайн»", .automaticOffline)
        text(6, "Отправлять статус офлайн через 3 секунды после отправки сообщения, реакции или отметки о прочтении. Повторное действие запускает таймер заново. Отображение статуса зависит от сети и сервера.")
        toggle(7, "Читать при действиях", .readOnAction)
        text(7, "Отмечать текущий чат прочитанным при отправке сообщения или реакции, даже если включено «Не читать сообщения».")
        text(8, "Разработчик — @rayzen_ezz", link: true)
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Настройки GhostGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: true), ()))
    }
    return ItemListController(context: context, state: signal)
}
