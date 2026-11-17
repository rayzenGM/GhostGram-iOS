import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private enum GhostGramPage: String {
    case home = "GhostGram", privacy = "Режим призрака", appearance = "Оформление", other = "Другое"
}

private final class GhostGramArguments {
    let openPage: (GhostGramPage) -> Void

    init(openPage: @escaping (GhostGramPage) -> Void) {
        self.openPage = openPage
    }
}

private struct GhostGramEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let option: GhostGramOption?
    let value: Bool
    let isLink: Bool
    var page: GhostGramPage? = nil
    var isHeader = false
    var isHero = false

    static func < (lhs: GhostGramEntry, rhs: GhostGramEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if self.isHero {
            return InfoListItem(presentationData: presentationData, systemStyle: .glass, title: "GhostGram", text: .plain("Telegram с настройками приватности"), style: .blocks, hasDecorations: false, closeAction: nil)
        } else if self.isHeader {
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        } else if let page = self.page {
            let symbol = page == .privacy ? "eye.slash" : (page == .appearance ? "paintpalette" : "star")
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: UIImage(systemName: symbol), title: self.title, label: "", sectionId: self.section, style: .blocks, action: {
                (arguments as! GhostGramArguments).openPage(page)
            })
        } else if let option = self.option {
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
    return ghostGramPageController(context: context, page: .home)
}

private func ghostGramPageController(context: AccountContext, page: GhostGramPage) -> ViewController {
    if page == .appearance { return ghostGramIconController(context: context) }
    var push: ((ViewController) -> Void)?
    let arguments = GhostGramArguments(openPage: { page in
        push?(ghostGramPageController(context: context, page: page))
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, GhostGramSettings.shared.signal)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = GhostGramSettings.shared
        var entries: [GhostGramEntry] = []
        func text(_ section: Int32, _ title: String, link: Bool = false, header: Bool = false, hero: Bool = false) {
            entries.append(GhostGramEntry(stableId: Int32(entries.count), section: section, title: title, option: nil, value: false, isLink: link, isHeader: header, isHero: hero))
        }
        func toggle(_ section: Int32, _ title: String, _ option: GhostGramOption) {
            entries.append(GhostGramEntry(stableId: Int32(entries.count), section: section, title: title, option: option, value: settings.value(option), isLink: false))
        }
        if page == .home {
            text(0, "GhostGram", hero: true)
            text(1, "Категории", header: true)
            for category in [GhostGramPage.privacy, .appearance, .other] {
                entries.append(GhostGramEntry(stableId: Int32(entries.count), section: 1, title: category == .privacy ? "GhostGram" : category.rawValue, option: nil, value: false, isLink: false, page: category))
            }
            text(2, "Ссылки", header: true)
            text(2, "Разработчик — @rayzen_ezz", link: true)
        } else if page == .other {
            toggle(0, "Локальный Telegram Premium", .localPremium)
            text(0, "Включает локальное оформление Premium и дополнительные иконки. Подписка не оформляется: серверные функции и лимиты остаются прежними. Некоторые изменения видны после повторного открытия экрана.")
            toggle(1, "Отключить рекламу", .hideAds)
            text(1, "Скрывает рекламные сообщения Telegram в чатах.")
        } else {
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
        text(7, "При отправке сообщения отмечать чат прочитанным. После успешной реакции — читать до сообщения с реакцией. Работает вместе с «Не читать сообщения».")
        text(8, "Режим шпиона", header: true)
        toggle(8, "Сохранять удалённые сообщения", .saveDeleted)
        toggle(8, "Сохранять историю правок", .saveEdits)
        toggle(9, "Сохранять в чатах с ботами", .saveInBots)
        text(9, "До 1000 снимков сохраняются только в памяти до завершения приложения. После нового запуска удалённые сообщения и старые версии исчезнут. Сворачивание не очищает историю, но iOS может завершить приложение в фоне.")
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(page.rawValue), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    push = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}

private struct GhostGramIconEntry: ItemListNodeEntry {
    let stableId: Int32 = 0
    let section: ItemListSectionId = 0
    let selected: String?
    static func < (lhs: GhostGramIconEntry, rhs: GhostGramIconEntry) -> Bool { return lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! GhostGramIconArguments
        return ThemeSettingsAppIconItem(theme: presentationData.theme, strings: presentationData.strings, systemStyle: .glass, sectionId: 0, icons: args.icons, isPremium: true, currentIconName: self.selected, updated: args.select)
    }
}

private final class GhostGramIconArguments {
    let icons: [PresentationAppIcon]
    let select: (PresentationAppIcon) -> Void
    init(icons: [PresentationAppIcon], select: @escaping (PresentationAppIcon) -> Void) {
        self.icons = icons
        self.select = select
    }
}

private func ghostGramIconController(context: AccountContext) -> ViewController {
    let bindings = context.sharedContext.applicationBindings
    let selected = ValuePromise<String?>(bindings.getAlternateIconName() ?? bindings.getAvailableAlternateIcons().first(where: { $0.isDefault })?.name)
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, selected.get(), context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)), GhostGramSettings.shared.signal)
    |> map { presentationData, current, peer, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let premium = (peer?.isPremium ?? false) || GhostGramSettings.shared.value(.localPremium)
        let icons = bindings.getAvailableAlternateIcons().filter { !$0.isPremium || premium }
        let arguments = GhostGramIconArguments(icons: icons, select: { icon in
            bindings.requestSetAlternateIconName(icon.isDefault ? nil : icon.name, { success in
                DispatchQueue.main.async {
                    selected.set(bindings.getAlternateIconName() ?? icons.first(where: { $0.isDefault })?.name)
                    if !success {
                        let alert = UIAlertController(title: "GhostGram", message: "Не удалось сменить иконку. Попробуйте ещё раз.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        bindings.presentNativeController(alert)
                    }
                }
            })
        })
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Оформление"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: [GhostGramIconEntry(selected: current)], style: .blocks, animateChanges: true), arguments))
    }
    return ItemListController(context: context, state: signal)
}
