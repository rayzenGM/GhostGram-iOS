import Foundation
import Postbox
import SwiftSignalKit

// Session-only presentation snapshots. Never write these to Postbox/UserDefaults:
// the server's deletion/edit still runs normally and a new process starts empty.
public final class GhostGramSessionHistory {
    public static let shared = GhostGramSessionHistory()
    private struct Snapshot {
        let accountId: PeerId
        let originalId: MessageId
        let deleted: Bool
        let botChat: Bool
        let message: Message
    }
    private let lock = NSLock()
    private var snapshots: [Snapshot] = []
    private var serial: UInt32 = 0
    private let changes = ValuePromise<Int>(0)
    private var revision = 0
    public var signal: Signal<Int, NoError> { self.changes.get() }

    public static func isPreview(_ id: MessageId) -> Bool {
        return id.namespace == Namespaces.Message.Local && id.id < 0
    }

    func capture(accountId: PeerId, message: Message, deleted: Bool, peer: Peer?) {
        let settings = GhostGramSettings.shared
        guard settings.value(deleted ? .saveDeleted : .saveEdits) else { return }
        let botChat = (peer as? TelegramUser)?.botInfo != nil
        guard !botChat || settings.value(.saveInBots) else { return }
        // View-once and timed content retain their normal expiry semantics.
        guard !message.attributes.contains(where: { $0 is AutoclearTimeoutMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute }) else { return }
        self.lock.lock()
        if deleted && self.snapshots.contains(where: { $0.accountId == accountId && $0.originalId == message.id && $0.deleted }) {
            self.lock.unlock()
            return
        }
        self.serial &+= 1
        let serial = self.serial
        let label = deleted ? "Удалено" : "До изменения"
        let text = message.text + "\n\n[" + label + "]"
        // Separate local identity prevents this preview from issuing server actions
        // for the deleted message, and keeps edit snapshots out of album grouping.
        let preview = Message(stableId: 0xf0000000 | (serial & 0x0fffffff), stableVersion: 0,
            id: MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: -Int32(serial & 0x7fffffff)),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: message.threadId,
            timestamp: message.timestamp, flags: message.flags.contains(.Incoming) ? [.Incoming] : [],
            tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil,
            author: message.author, text: text,
            attributes: message.attributes.filter { $0 is TextEntitiesMessageAttribute },
            media: message.media, peers: message.peers,
            associatedMessages: SimpleDictionary<MessageId, Message>(), associatedMessageIds: [],
            associatedMedia: message.associatedMedia, associatedThreadInfo: message.associatedThreadInfo, associatedStories: [:])
        self.snapshots.append(Snapshot(accountId: accountId, originalId: message.id, deleted: deleted, botChat: botChat, message: preview))
        // Bound metadata on memory-constrained devices; media bytes aren't copied.
        if self.snapshots.count > 1000 { self.snapshots.removeFirst(self.snapshots.count - 1000) }
        self.revision += 1
        let revision = self.revision
        self.lock.unlock()
        self.changes.set(revision)
    }

    public func messages(accountId: PeerId, peerId: PeerId, threadId: Int64?) -> [Message] {
        let settings = GhostGramSettings.shared
        let deleted = settings.value(.saveDeleted)
        let edits = settings.value(.saveEdits)
        let bots = settings.value(.saveInBots)
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.snapshots.filter {
            $0.accountId == accountId && $0.originalId.peerId == peerId &&
            (threadId == nil || $0.message.threadId == threadId) &&
            ($0.deleted ? deleted : edits) && (!$0.botChat || bots)
        }.map { $0.message }
    }

    public func clear(accountId: PeerId? = nil) {
        self.lock.lock()
        if let accountId { self.snapshots.removeAll { $0.accountId == accountId } }
        else { self.snapshots.removeAll() }
        self.revision += 1
        let revision = self.revision
        self.lock.unlock()
        self.changes.set(revision)
    }
}
