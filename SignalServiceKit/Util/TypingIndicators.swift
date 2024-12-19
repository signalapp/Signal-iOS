//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol TypingIndicators: AnyObject {
    var keyValueStore: KeyValueStore { get }

    func warmCaches()

    func didStartTypingOutgoingInput(inThread thread: TSThread)

    func didSendOutgoingMessage(inThread thread: TSThread)

    func didReceiveTypingStartedMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32)

    func didReceiveTypingStoppedMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32)

    func didReceiveIncomingMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32)

    // Returns the address of the user who should currently be shown typing for a given thread.
    //
    // If no one is typing in that thread, returns nil.
    // If multiple users are typing in that thread, returns the user to show.
    //
    // TODO: Use this method.
    func typingAddress(forThread thread: TSThread) -> SignalServiceAddress?

    func setTypingIndicatorsEnabledAndSendSyncMessage(value: Bool)

    func setTypingIndicatorsEnabled(value: Bool, transaction: SDSAnyWriteTransaction)

    func areTypingIndicatorsEnabled() -> Bool
}

// MARK: -

public class TypingIndicatorsImpl: NSObject, TypingIndicators {

    public static let typingIndicatorStateDidChange = Notification.Name("typingIndicatorStateDidChange")

    private let kDatabaseKey_TypingIndicatorsEnabled = "kDatabaseKey_TypingIndicatorsEnabled"

    private let _areTypingIndicatorsEnabled = AtomicBool(false, lock: .sharedGlobal)

    public let keyValueStore = KeyValueStore(collection: "TypingIndicators")

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let enabled = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.keyValueStore.getBool(
                self.kDatabaseKey_TypingIndicatorsEnabled,
                defaultValue: true,
                transaction: transaction.asV2Read
            )
        }

        _areTypingIndicatorsEnabled.set(enabled)
    }

    public func setTypingIndicatorsEnabledAndSendSyncMessage(value: Bool) {
        Logger.info("\(_areTypingIndicatorsEnabled.get()) -> \(value)")
        _areTypingIndicatorsEnabled.set(value)

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setBool(value,
                                       key: self.kDatabaseKey_TypingIndicatorsEnabled,
                                       transaction: transaction.asV2Write)
        }

        SSKEnvironment.shared.syncManagerRef.sendConfigurationSyncMessage()

        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()

        NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: nil)
    }

    public func setTypingIndicatorsEnabled(value: Bool, transaction: SDSAnyWriteTransaction) {
        Logger.info("\(_areTypingIndicatorsEnabled.get()) -> \(value)")
        _areTypingIndicatorsEnabled.set(value)

        keyValueStore.setBool(value,
                              key: kDatabaseKey_TypingIndicatorsEnabled,
                              transaction: transaction.asV2Write)

        NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: nil)
    }

    public func areTypingIndicatorsEnabled() -> Bool {
        return _areTypingIndicatorsEnabled.get()
    }

    // MARK: -

    public func didStartTypingOutgoingInput(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didStartTypingOutgoingInput()
    }

    public func didSendOutgoingMessage(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didSendOutgoingMessage()
    }

    public func didReceiveTypingStartedMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32) {
        AssertIsOnMainThread()
        ensureIncomingIndicators(forThread: thread, senderAci: senderAci, deviceId: deviceId)
            .didReceiveTypingStartedMessage()
    }

    public func didReceiveTypingStoppedMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32) {
        AssertIsOnMainThread()
        ensureIncomingIndicators(forThread: thread, senderAci: senderAci, deviceId: deviceId)
            .didReceiveTypingStoppedMessage()
    }

    public func didReceiveIncomingMessage(inThread thread: TSThread, senderAci: Aci, deviceId: UInt32) {
        AssertIsOnMainThread()
        ensureIncomingIndicators(forThread: thread, senderAci: senderAci, deviceId: deviceId)
            .didReceiveIncomingMessage()
    }

    public func typingAddress(forThread thread: TSThread) -> SignalServiceAddress? {
        AssertIsOnMainThread()

        guard areTypingIndicatorsEnabled() else {
            return nil
        }

        var firstAddress: SignalServiceAddress?
        var firstTimestamp: UInt64?

        let threadKey = incomingIndicatorsKey(forThread: thread)
        guard let deviceMap = incomingIndicatorsMap[threadKey] else {
            // No devices are typing in this thread.
            return nil
        }
        for incomingIndicators in deviceMap.values {
            guard incomingIndicators.isTyping else {
                continue
            }
            guard let startedTypingTimestamp = incomingIndicators.startedTypingTimestamp else {
                owsFailDebug("Typing device is missing start timestamp.")
                continue
            }
            if let firstTimestamp = firstTimestamp,
                firstTimestamp < startedTypingTimestamp {
                // More than one recipient/device is typing in this conversation;
                // prefer the one that started typing first.
                continue
            }
            firstAddress = SignalServiceAddress(incomingIndicators.senderAci)
            firstTimestamp = startedTypingTimestamp
        }
        return firstAddress
    }

    // MARK: -

    // Map of thread id-to-OutgoingIndicators.
    private var outgoingIndicatorsMap = [String: OutgoingIndicators]()

    private func ensureOutgoingIndicators(forThread thread: TSThread) -> OutgoingIndicators? {
        AssertIsOnMainThread()

        if let outgoingIndicators = outgoingIndicatorsMap[thread.uniqueId] {
            return outgoingIndicators
        }
        let outgoingIndicators = OutgoingIndicators(delegate: self, thread: thread)
        outgoingIndicatorsMap[thread.uniqueId] = outgoingIndicators
        return outgoingIndicators
    }

    // The sender maintains two timers per chat:
    //
    // A sendPause timer
    // A sendRefresh timer
    private class OutgoingIndicators {
        private weak var delegate: TypingIndicators?
        private let threadUniqueId: String
        private var sendPauseTimer: Timer?
        private var sendRefreshTimer: Timer?

        init(delegate: TypingIndicators, thread: TSThread) {
            self.delegate = delegate
            self.threadUniqueId = thread.uniqueId
        }

        func didStartTypingOutgoingInput() {
            AssertIsOnMainThread()

            if sendRefreshTimer == nil {
                // If the user types a character into the compose box, and the sendRefresh timer isn’t running:

                sendTypingMessageIfNecessary(for: threadUniqueId, action: .started)

                sendRefreshTimer?.invalidate()
                sendRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                    self?.sendRefreshTimerDidFire()
                }
            } else {
                // If the user types a character into the compose box, and the sendRefresh timer is running:
            }

            sendPauseTimer?.invalidate()
            sendPauseTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                self?.sendPauseTimerDidFire()
            }
        }

        func sendPauseTimerDidFire() {
            AssertIsOnMainThread()

            sendTypingMessageIfNecessary(for: threadUniqueId, action: .stopped)

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil

            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        func sendRefreshTimerDidFire() {
            AssertIsOnMainThread()

            sendTypingMessageIfNecessary(for: threadUniqueId, action: .started)

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                self?.sendRefreshTimerDidFire()
            }
        }

        func didSendOutgoingMessage() {
            AssertIsOnMainThread()

            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil

            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        private func sendTypingMessageIfNecessary(for threadUniqueId: String, action: TypingIndicatorAction) {
            guard let delegate = delegate else {
                return owsFailDebug("Missing delegate.")
            }
            // `areTypingIndicatorsEnabled` reflects the user-facing setting in the app preferences.
            // If it's disabled we don't want to emit "typing indicator" messages
            // or show typing indicators for other users.
            guard delegate.areTypingIndicatorsEnabled() else { return }

            SSKEnvironment.shared.databaseStorageRef.write(.promise) { transaction in
                guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                    return Promise<Void>.value(())
                }

                let message = TypingIndicatorMessage(thread: thread, action: action, transaction: transaction)
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message
                )

                return SSKEnvironment.shared.messageSenderJobQueueRef.add(
                    .promise,
                    message: preparedMessage,
                    limitToCurrentProcessLifetime: true,
                    transaction: transaction
                )
            }.then(on: SyncScheduler()) { messageSendPromise in
                return messageSendPromise
            }.catch { error in
                Logger.error("Error: \(error)")
            }
        }
    }

    // MARK: -

    // Map of (thread id)-to-(recipient id and device id)-to-IncomingIndicators.
    private var incomingIndicatorsMap = [String: [AddressWithDeviceId: IncomingIndicators]]()
    private struct AddressWithDeviceId: Hashable {
        let aci: Aci
        let deviceId: UInt32
    }

    private func incomingIndicatorsKey(forThread thread: TSThread) -> String {
        return String(describing: thread.uniqueId)
    }

    private func incomingIndicatorsKey(aci: Aci, deviceId: UInt32) -> AddressWithDeviceId {
        return AddressWithDeviceId(aci: aci, deviceId: deviceId)
    }

    private func ensureIncomingIndicators(forThread thread: TSThread, senderAci: Aci, deviceId: UInt32) -> IncomingIndicators {
        AssertIsOnMainThread()

        let threadKey = incomingIndicatorsKey(forThread: thread)
        let deviceKey = incomingIndicatorsKey(aci: senderAci, deviceId: deviceId)
        guard let deviceMap = incomingIndicatorsMap[threadKey] else {
            let incomingIndicators = IncomingIndicators(delegate: self, thread: thread, senderAci: senderAci, deviceId: deviceId)
            incomingIndicatorsMap[threadKey] = [deviceKey: incomingIndicators]
            return incomingIndicators
        }
        guard let incomingIndicators = deviceMap[deviceKey] else {
            let incomingIndicators = IncomingIndicators(delegate: self, thread: thread, senderAci: senderAci, deviceId: deviceId)
            var deviceMapCopy = deviceMap
            deviceMapCopy[deviceKey] = incomingIndicators
            incomingIndicatorsMap[threadKey] = deviceMapCopy
            return incomingIndicators
        }
        return incomingIndicators
    }

    // The receiver maintains one timer for each (sender, device) in a chat:
    private class IncomingIndicators {
        private weak var delegate: TypingIndicators?
        private let thread: TSThread
        fileprivate let senderAci: Aci
        private let deviceId: UInt32
        private var displayTypingTimer: Timer?
        fileprivate var startedTypingTimestamp: UInt64?

        var isTyping = false {
            didSet {
                AssertIsOnMainThread()

                let didChange = oldValue != isTyping
                if didChange {
                    notifyIfNecessary()
                }
            }
        }

        init(delegate: TypingIndicators, thread: TSThread, senderAci: Aci, deviceId: UInt32) {
            self.delegate = delegate
            self.thread = thread
            self.senderAci = senderAci
            self.deviceId = deviceId
        }

        func didReceiveTypingStartedMessage() {
            AssertIsOnMainThread()

            displayTypingTimer?.invalidate()
            displayTypingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.displayTypingTimerDidFire()
            }
            if !isTyping {
                startedTypingTimestamp = NSDate.ows_millisecondTimeStamp()
            }
            isTyping = true
        }

        func didReceiveTypingStoppedMessage() {
            AssertIsOnMainThread()

            clearTyping()
        }

        func displayTypingTimerDidFire() {
            AssertIsOnMainThread()

            clearTyping()
        }

        func didReceiveIncomingMessage() {
            AssertIsOnMainThread()

            clearTyping()
        }

        private func clearTyping() {
            AssertIsOnMainThread()

            displayTypingTimer?.invalidate()
            displayTypingTimer = nil
            startedTypingTimestamp = nil
            isTyping = false
        }

        private func notifyIfNecessary() {
            guard let delegate = delegate else {
                owsFailDebug("Missing delegate.")
                return
            }
            // `areTypingIndicatorsEnabled` reflects the user-facing setting in the app preferences.
            // If it's disabled we don't want to emit "typing indicator" messages
            // or show typing indicators for other users.
            guard delegate.areTypingIndicatorsEnabled() else {
                return
            }
            NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: thread.uniqueId)
        }
    }
}
