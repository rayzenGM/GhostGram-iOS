import Foundation
import Postbox
import SwiftSignalKit

public enum GhostGramOption: String, CaseIterable {
    case enabled, hideRead, hideStoryRead, hideOnline, hideTyping, automaticOffline, readOnAction
    case saveDeleted, saveEdits, saveInBots, localPremium, hideAds
}

public final class GhostGramSettings {
    public static let shared = GhostGramSettings()
    private let defaults = UserDefaults.standard
    private let changes = ValuePromise<Int>(0)
    private let lock = NSRecursiveLock()
    private var revision = 0
    private var localAccounts: [PeerId: Int] = [:]

    func retainAccount(_ id: PeerId) {
        self.lock.lock()
        self.localAccounts[id, default: 0] += 1
        self.lock.unlock()
    }

    func releaseAccount(_ id: PeerId) {
        self.lock.lock()
        if let count = self.localAccounts[id], count > 1 { self.localAccounts[id] = count - 1 }
        else { self.localAccounts.removeValue(forKey: id) }
        self.lock.unlock()
    }

    func hasLocalPremium(_ id: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.localAccounts[id] != nil && self.value(.localPremium)
    }

    public func value(_ option: GhostGramOption) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.defaults.object(forKey: "GhostGram." + option.rawValue) as? Bool ?? [GhostGramOption.hideRead, .hideStoryRead, .hideOnline, .hideTyping, .automaticOffline].contains(option)
    }

    public func active(_ option: GhostGramOption) -> Bool {
        return self.value(.enabled) && self.value(option)
    }

    public func set(_ option: GhostGramOption, value: Bool) {
        self.lock.lock()
        self.defaults.set(value, forKey: "GhostGram." + option.rawValue)
        self.revision += 1
        self.changes.set(self.revision)
        self.lock.unlock()
    }

    public var signal: Signal<Int, NoError> { self.changes.get() }
}

// Only receipt RPCs are suppressed. History loading and server update processing
// must continue normally. Completion retires the local receipt operation without
// inventing a server pts value or retrying a deliberately suppressed request.
func ghostGramSuppressRequest(_ name: String, allowRead: Bool) -> Bool {
    let settings = GhostGramSettings.shared
    if settings.active(.hideTyping) && (name == "messages.setTyping" || name == "messages.setEncryptedTyping") {
        return true
    }
    if settings.active(.hideStoryRead) && (name == "stories.readStories" || name == "stories.incrementStoryViews") {
        return true
    }
    if !allowRead && settings.active(.hideRead) {
        switch name {
        case "messages.readHistory", "channels.readHistory", "messages.readSavedHistory", "messages.readDiscussion", "messages.readMessageContents", "channels.readMessageContents", "messages.readEncryptedHistory", "messages.readMentions", "messages.readReactions":
            return true
        default:
            break
        }
    }
    return false
}

func ghostGramRevealsPresence(_ name: String) -> Bool {
    switch name {
    case "messages.sendMessage", "messages.sendMedia", "messages.sendMultiMedia", "messages.forwardMessages", "messages.sendInlineBotResult", "messages.sendReaction", "messages.sendPaidReaction", "messages.sendEncrypted", "messages.sendEncryptedFile", "messages.readHistory", "channels.readHistory", "messages.readSavedHistory", "messages.readDiscussion", "messages.readMessageContents", "channels.readMessageContents", "messages.readEncryptedHistory":
        return true
    default:
        return false
    }
}
