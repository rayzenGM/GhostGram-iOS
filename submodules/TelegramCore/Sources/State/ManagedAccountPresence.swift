import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var activityDisposable: Disposable?
    private var actionTimer: SignalKitTimer?
    private var selfPresenceDisposable: Disposable?
    private var selfOnlineUntil: Int32 = 0
    private var needsGhostOffline = false
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox, accountPeerId: PeerId) {
        self.queue = queue
        self.network = network
        
        self.shouldKeepOnlinePresenceDisposable = (combineLatest(shouldKeepOnlinePresence |> distinctUntilChanged, GhostGramSettings.shared.signal)
        |> deliverOn(self.queue)).start(next: { [weak self] value, _ in
            guard let self else { return }
            self.actionTimer?.invalidate()
            self.actionTimer = nil
            let settings = GhostGramSettings.shared
            let online = value && !settings.active(.hideOnline)
            self.updatePresence(online)
            self.needsGhostOffline = online
            if settings.active(.automaticOffline) { self.startGhostOfflineTimer() }
        })
        self.selfPresenceDisposable = (postbox.peerView(id: accountPeerId)
        |> deliverOn(self.queue)).start(next: { [weak self] view in
            guard let self else { return }
            if let presence = view.peerPresences[accountPeerId] as? TelegramUserPresence, case let .present(until) = presence.status {
                self.selfOnlineUntil = until
            } else {
                self.selfOnlineUntil = 0
            }
        })
        self.activityDisposable = (network.ghostGramActivity.signal()
        |> deliverOn(self.queue)).start(next: { [weak self] _ in
            guard let self, GhostGramSettings.shared.active(.automaticOffline) else { return }
            self.needsGhostOffline = true
            self.startGhostOfflineTimer()
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.activityDisposable?.dispose()
        self.selfPresenceDisposable?.dispose()
        self.actionTimer?.invalidate()
        self.onlineTimer?.invalidate()
    }
    
    // AyuGram-style worker: successful revealing actions reset a three-second
    // interval; self-presence updates also catch online status outside those RPCs.
    private func startGhostOfflineTimer() {
        self.actionTimer?.invalidate()
        let timer = SignalKitTimer(timeout: 3.0, repeat: true, completion: { [weak self] in
            guard let self, GhostGramSettings.shared.active(.automaticOffline) else { return }
            if self.needsGhostOffline || self.selfOnlineUntil > Int32(Date().timeIntervalSince1970) {
                self.needsGhostOffline = false
                self.selfOnlineUntil = 0
                self.updatePresence(false)
            }
        }, queue: self.queue)
        self.actionTimer = timer
        timer.start()
    }

    private func updatePresence(_ isOnline: Bool) {
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            if !isOnline, case .boolFalse = result {
                self?.needsGhostOffline = true
            }
        }, completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox, accountPeerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, postbox: postbox, accountPeerId: accountPeerId)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
