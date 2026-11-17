import Foundation
import XCTest
import SwiftSignalKit
@testable import TelegramApi
@testable import TelegramCore

final class GhostGramPrivacyTests: XCTestCase {
    private var previous: [GhostGramOption: Bool] = [:]

    override func setUp() {
        super.setUp()
        for option in GhostGramOption.allCases {
            self.previous[option] = GhostGramSettings.shared.value(option)
            GhostGramSettings.shared.set(option, value: true)
        }
    }

    override func tearDown() {
        for (option, value) in self.previous {
            GhostGramSettings.shared.set(option, value: value)
        }
        super.tearDown()
    }

    func testSuppressedReceiptCompletesWithoutTouchingTransportOrInventingPts() {
        let server = ScriptedServer()
        let network = Network.makeForTesting(engine: server, basePath: NSTemporaryDirectory() + UUID().uuidString, encryptionProvider: UnusedEncryptionProvider())
        let completed = self.expectation(description: "local receipt retired")
        let disposable = network.request(Api.functions.messages.readHistory(peer: .inputPeerSelf, maxId: 42)).start(next: { _ in
            XCTFail("Suppression must not fabricate a server response")
        }, error: { _ in
            XCTFail("Suppression must not trigger retryRequest")
        }, completed: { completed.fulfill() })
        self.wait(for: [completed], timeout: 1.0)
        XCTAssertTrue(server.requests.isEmpty)
        disposable.dispose()
    }

    func testExplicitReadBypassIsOneRequestNotAGlobalPermission() {
        let server = ScriptedServer()
        let network = Network.makeForTesting(engine: server, basePath: NSTemporaryDirectory() + UUID().uuidString, encryptionProvider: UnusedEncryptionProvider())
        let allowed = network.request(Api.functions.messages.readHistory(peer: .inputPeerSelf, maxId: 10), ghostAllowRead: true).start()
        let hidden = network.request(Api.functions.messages.readHistory(peer: .inputPeerSelf, maxId: 20)).start()
        XCTAssertEqual(server.requestNames, ["messages.readHistory"])
        allowed.dispose()
        hidden.dispose()
    }

    func testMasterOffRestoresTransportAndKeepsIndividualChoices() {
        GhostGramSettings.shared.set(.enabled, value: false)
        XCTAssertFalse(ghostGramSuppressRequest("messages.readHistory", allowRead: false))
        XCTAssertFalse(ghostGramSuppressRequest("stories.readStories", allowRead: false))
        XCTAssertFalse(ghostGramSuppressRequest("messages.setTyping", allowRead: false))
        XCTAssertTrue(GhostGramSettings.shared.value(.hideRead))
    }

    func testReadBypassNeverAllowsTypingOrStoryViews() {
        XCTAssertFalse(ghostGramSuppressRequest("messages.readHistory", allowRead: true))
        XCTAssertTrue(ghostGramSuppressRequest("messages.setTyping", allowRead: true))
        XCTAssertTrue(ghostGramSuppressRequest("stories.readStories", allowRead: true))
        XCTAssertFalse(ghostGramSuppressRequest("messages.getHistory", allowRead: false))
        XCTAssertFalse(ghostGramSuppressRequest("updates.getDifference", allowRead: false))
    }
}
