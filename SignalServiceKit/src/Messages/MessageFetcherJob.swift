//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// This token can be used to observe the completion of a given fetch cycle.
public struct MessageFetchCycle: Hashable, Equatable {
    public let uuid = UUID()
    public let promise: Promise<Void>

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    // MARK: Equatable

    public static func == (lhs: MessageFetchCycle, rhs: MessageFetchCycle) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

// MARK: -

public class MessageFetcherJob: NSObject {

    private var timer: Timer?

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        if CurrentAppContext().shouldProcessIncomingMessages && CurrentAppContext().isMainApp {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                // Fetch messages as soon as possible after launching. In particular, when
                // launching from the background, without this, we end up waiting some extra
                // seconds before receiving an actionable push notification.
                if Self.tsAccountManager.isRegistered {
                    firstly(on: .global()) {
                        self.run()
                    }.catch(on: .global()) { error in
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            }
        }
    }

    // MARK: -

    // This operation queue ensures that only one fetch operation is
    // running at a given time.
    private let fetchOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "MessageFetcherJob.fetchOperationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    fileprivate var activeOperationCount: Int {
        return fetchOperationQueue.operationCount
    }

    private let unfairLock = UnfairLock()

    private let completionQueue = DispatchQueue(label: "org.signal.messageFetcherJob.completionQueue")

    // This property should only be accessed with unfairLock acquired.
    private var activeFetchCycles = Set<UUID>()

    // This property should only be accessed with unfairLock acquired.
    private var completedFetchCyclesCounter: UInt = 0

    @objc
    public static let didChangeStateNotificationName = Notification.Name("MessageFetcherJob.didChangeStateNotificationName")

    @discardableResult
    public func run() -> MessageFetchCycle {
        Logger.debug("")

        // Use an operation queue to ensure that only one fetch cycle is done
        // at a time.
        let fetchOperation = MessageFetchOperation(job: self)
        let promise = fetchOperation.promise
        let fetchCycle = MessageFetchCycle(promise: promise)

        _ = self.unfairLock.withLock {
            activeFetchCycles.insert(fetchCycle.uuid)
        }

        fetchOperationQueue.addOperation(fetchOperation)

        completionQueue.async {
            self.fetchOperationQueue.waitUntilAllOperationsAreFinished()

            self.unfairLock.withLock {
                self.activeFetchCycles.remove(fetchCycle.uuid)
                self.completedFetchCyclesCounter += 1
            }

            self.postDidChangeState()
        }

        self.postDidChangeState()

        return fetchCycle
    }

    @objc
    @discardableResult
    public func runObjc() -> AnyPromise {
        AnyPromise(run().promise)
    }

    private func postDidChangeState() {
        NotificationCenter.default.postNotificationNameAsync(MessageFetcherJob.didChangeStateNotificationName, object: nil)
    }

    public func isFetchCycleComplete(fetchCycle: MessageFetchCycle) -> Bool {
        unfairLock.withLock {
            self.activeFetchCycles.contains(fetchCycle.uuid)
        }
    }

    public var areAllFetchCyclesComplete: Bool {
        unfairLock.withLock {
            self.activeFetchCycles.isEmpty
        }
    }

    public var completedRestFetches: UInt {
        unfairLock.withLock {
            self.completedFetchCyclesCounter
        }
    }

    @objc
    public var hasCompletedInitialFetch: Bool {
        (SocketManager.shared.socketState(forType: .default) == .open &&
            SocketManager.shared.hasEmptiedInitialQueue)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func fetchingCompletePromise() -> AnyPromise {
        return AnyPromise(fetchingCompletePromise())
    }

    public func fetchingCompletePromise() -> Promise<Void> {
        guard CurrentAppContext().shouldProcessIncomingMessages else {
            if DebugFlags.isMessageProcessingVerbose {
                Logger.verbose("!shouldProcessIncomingMessages")
            }
            return Promise.value(())
        }

        guard !hasCompletedInitialFetch else {
            if DebugFlags.isMessageProcessingVerbose {
                Logger.verbose("hasCompletedInitialFetch")
            }
            return Promise.value(())
        }

        if DebugFlags.isMessageProcessingVerbose {
            Logger.verbose("!hasCompletedInitialFetch")
        }

        return NotificationCenter.default.observe(once: .webSocketStateDidChange).then { _ in
            return self.fetchingCompletePromise()
        }.asVoid()
    }

    // MARK: -

    fileprivate func fetchMessages(resolver: Resolver<Void>) {
        Logger.debug("")

        guard tsAccountManager.isRegisteredAndReady else {
            assert(AppReadiness.isAppReady)
            Logger.warn("Not registered.")
            return resolver.fulfill(())
        }

        // Delegate message fetching to SocketManager.
        if hasCompletedInitialFetch {
            // If the websocket is already open & has drained
            // it's initial queue, wait a bit before fulfilling
            // to give the websocket time to receive any new
            // incoming messages.
            //
            // TODO: Is this necessary?
            let minimumInterval: TimeInterval = 0.5
            DispatchQueue.global().asyncAfter(deadline: .now() + minimumInterval) {
                resolver.fulfill(())
            }
        } else {
            return Self.tryToResolveFetch(resolver: resolver,
                                          startDate: Date(),
                                          hasRequestedOpen: AtomicBool(false))
        }
    }

    fileprivate class func tryToResolveFetch(resolver: Resolver<Void>,
                                             startDate: Date,
                                             hasRequestedOpen: AtomicBool) {
        Logger.debug("")

        let socketState = socketManager.socketState(forType: .default)
        if socketState == .open {
            if socketManager.hasEmptiedInitialQueue {
                resolver.fulfill(())
                return
            }
        } else if hasRequestedOpen.tryToSetFlag() {
            // If we haven't requested that the default websocket open yet,
            // do so now.
            socketManager.requestSocketOpen()
        }

        let timeoutInterval: TimeInterval = kSecondInterval * 30
        guard abs(startDate.timeIntervalSinceNow) < timeoutInterval else {
            // We don't need to bother rejecting.
            resolver.fulfill(())
            return
        }

        // Wait a bit longer for the socket to open and drain its initial queue.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            Self.tryToResolveFetch(resolver: resolver, startDate: startDate, hasRequestedOpen: hasRequestedOpen)
        }
    }

    // MARK: - Run Loop

    // use in DEBUG or wherever you can't receive push notifications to poll for messages.
    // Do not use in production.
    public func startRunLoop(timeInterval: Double) {
        Logger.error("Starting message fetch polling. This should not be used in production.")
        timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) {[weak self] _ in
            _ = self?.run()
            return
        }
    }

    public func stopRunLoop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: -

private class MessageFetchOperation: OWSOperation {

    private weak var job: MessageFetcherJob?

    let promise: Promise<Void>
    private let resolver: Resolver<Void>

    required init(job: MessageFetcherJob) {
        self.job = job

        let (promise, resolver) = Promise<Void>.pending()
        self.promise = promise
        self.resolver = resolver
        super.init()
        self.remainingRetries = 3
    }

    public override func run() {
        Logger.debug("")

        if let job = job {
            job.fetchMessages(resolver: resolver)
        } else {
            resolver.reject(OWSAssertionError("Missing job."))
        }

        _ = promise.ensure(on: .global()) {
            self.reportSuccess()
        }
    }
}
