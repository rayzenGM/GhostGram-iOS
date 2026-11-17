import XCTest
import Postbox
@testable import TelegramCore

final class GhostGramSessionHistoryTests: XCTestCase {
    private var previous: [GhostGramOption: Bool] = [:]
    private let account = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let otherAccount = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let chat = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(3))

    override func setUp() {
        super.setUp()
        for option in [GhostGramOption.saveDeleted, .saveEdits, .saveInBots] {
            previous[option] = GhostGramSettings.shared.value(option)
            GhostGramSettings.shared.set(option, value: true)
        }
    }
    override func tearDown() {
        for (option, value) in previous { GhostGramSettings.shared.set(option, value: value) }
        super.tearDown()
    }
    private func message(_ id: Int32, text: String = "original", threadId: Int64? = nil) -> Message {
        return Message(stableId: UInt32(id), stableVersion: 0,
            id: MessageId(peerId: chat, namespace: Namespaces.Message.Cloud, id: id),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: threadId,
            timestamp: 100, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [],
            forwardInfo: nil, author: nil, text: text, attributes: [], media: [],
            peers: SimpleDictionary<PeerId, Peer>(), associatedMessages: SimpleDictionary<MessageId, Message>(),
            associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }
    func testSnapshotsAreAccountScopedAndNewSessionIsEmpty() {
        let store = GhostGramSessionHistory()
        store.capture(accountId: account, message: message(1), deleted: true, peer: nil)
        XCTAssertEqual(store.messages(accountId: account, peerId: chat, threadId: nil).count, 1)
        XCTAssertTrue(store.messages(accountId: otherAccount, peerId: chat, threadId: nil).isEmpty)
        XCTAssertTrue(GhostGramSessionHistory().messages(accountId: account, peerId: chat, threadId: nil).isEmpty)
        store.clear()
        XCTAssertTrue(store.messages(accountId: account, peerId: chat, threadId: nil).isEmpty)
    }
    func testDuplicateDeletionAndDisabledCapture() {
        let store = GhostGramSessionHistory()
        let original = message(1)
        store.capture(accountId: account, message: original, deleted: true, peer: nil)
        store.capture(accountId: account, message: original, deleted: true, peer: nil)
        let saved = store.messages(accountId: account, peerId: chat, threadId: nil)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id.namespace, Namespaces.Message.Local)
        XCTAssertFalse(saved.first?.flags.contains(.Unsent) ?? true)
        XCTAssertEqual(original.text, "original")
        GhostGramSettings.shared.set(.saveDeleted, value: false)
        store.capture(accountId: account, message: message(2), deleted: true, peer: nil)
        XCTAssertTrue(store.messages(accountId: account, peerId: chat, threadId: nil).isEmpty)
        GhostGramSettings.shared.set(.saveDeleted, value: true)
        XCTAssertEqual(store.messages(accountId: account, peerId: chat, threadId: nil).count, 1)
    }
    func testEditVersionsAndForumTopicsStaySeparate() {
        let store = GhostGramSessionHistory()
        store.capture(accountId: account, message: message(1, text: "first", threadId: 10), deleted: false, peer: nil)
        store.capture(accountId: account, message: message(1, text: "second", threadId: 10), deleted: false, peer: nil)
        let edits = store.messages(accountId: account, peerId: chat, threadId: 10)
        XCTAssertEqual(edits.count, 2)
        XCTAssertNotEqual(edits[0].id, edits[1].id)
        XCTAssertTrue(edits[0].text.contains("first"))
        XCTAssertTrue(store.messages(accountId: account, peerId: chat, threadId: 20).isEmpty)
    }
    func testMemoryBoundRetainsNewestSnapshots() {
        let store = GhostGramSessionHistory()
        for i in 1 ... 1002 { store.capture(accountId: account, message: message(Int32(i)), deleted: true, peer: nil) }
        XCTAssertEqual(store.messages(accountId: account, peerId: chat, threadId: nil).count, 1000)
    }
}
