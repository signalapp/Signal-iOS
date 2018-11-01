//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSTypingIndicators)
public protocol TypingIndicators: class {
    @objc
    func didStartTypingOutgoingInput(inThread thread: TSThread)

    @objc
    func didStopTypingOutgoingInput(inThread thread: TSThread)

    @objc
    func didSendOutgoingMessage(inThread thread: TSThread)

    @objc
    func didReceiveTypingStartedMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt)

    @objc
    func didReceiveTypingStoppedMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt)

    @objc
    func didReceiveIncomingMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt)

    // TODO: Use this method.
    @objc
    func areTypingIndicatorsVisible(inThread thread: TSThread, recipientId: String) -> Bool

    @objc
    func setTypingIndicatorsEnabled(value: Bool)

    @objc
    func areTypingIndicatorsEnabled() -> Bool
}

// MARK: -

@objc(OWSTypingIndicatorsImpl)
public class TypingIndicatorsImpl: NSObject, TypingIndicators {

    @objc public static let typingIndicatorStateDidChange = Notification.Name("typingIndicatorStateDidChange")

    private let kDatabaseCollection = "TypingIndicators"
    private let kDatabaseKey_TypingIndicatorsEnabled = "kDatabaseKey_TypingIndicatorsEnabled"

    private var _areTypingIndicatorsEnabled = false

    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppIsReady {
            self.setup()
        }
    }

    private func setup() {
        AssertIsOnMainThread()

        _areTypingIndicatorsEnabled = primaryStorage.dbReadConnection.bool(forKey: kDatabaseKey_TypingIndicatorsEnabled, inCollection: kDatabaseCollection, defaultValue: true)
    }

    // MARK: - Dependencies

    private var primaryStorage: OWSPrimaryStorage {
        return SSKEnvironment.shared.primaryStorage
    }

    private var syncManager: OWSSyncManagerProtocol {
        return SSKEnvironment.shared.syncManager
    }

    // MARK: -

    @objc
    public func setTypingIndicatorsEnabled(value: Bool) {
        AssertIsOnMainThread()

        _areTypingIndicatorsEnabled = value

        primaryStorage.dbReadWriteConnection.setBool(value, forKey: kDatabaseKey_TypingIndicatorsEnabled, inCollection: kDatabaseCollection)
        
        syncManager.sendConfigurationSyncMessage()
    }

    @objc
    public func areTypingIndicatorsEnabled() -> Bool {
        AssertIsOnMainThread()

        return _areTypingIndicatorsEnabled
    }

    // MARK: -

    @objc
    public func didStartTypingOutgoingInput(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didStartTypingOutgoingInput()
    }

    @objc
    public func didStopTypingOutgoingInput(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didStopTypingOutgoingInput()
    }

    @objc
    public func didSendOutgoingMessage(inThread thread: TSThread) {
        AssertIsOnMainThread()
        guard let outgoingIndicators = ensureOutgoingIndicators(forThread: thread) else {
            owsFailDebug("Could not locate outgoing indicators state")
            return
        }
        outgoingIndicators.didSendOutgoingMessage()
    }

    @objc
    public func didReceiveTypingStartedMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt) {
        AssertIsOnMainThread()
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, recipientId: recipientId, deviceId: deviceId)
        incomingIndicators.didReceiveTypingStartedMessage()
    }

    @objc
    public func didReceiveTypingStoppedMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt) {
        AssertIsOnMainThread()
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, recipientId: recipientId, deviceId: deviceId)
        incomingIndicators.didReceiveTypingStoppedMessage()
    }

    @objc
    public func didReceiveIncomingMessage(inThread thread: TSThread, recipientId: String, deviceId: UInt) {
        AssertIsOnMainThread()
        let incomingIndicators = ensureIncomingIndicators(forThread: thread, recipientId: recipientId, deviceId: deviceId)
        incomingIndicators.didReceiveIncomingMessage()
    }

    @objc
    public func areTypingIndicatorsVisible(inThread thread: TSThread, recipientId: String) -> Bool {
        AssertIsOnMainThread()

        let key = incomingIndicatorsKey(forThread: thread, recipientId: recipientId)
        guard let deviceMap = incomingIndicatorsMap[key] else {
            return false
        }
        for incomingIndicators in deviceMap.values {
            if incomingIndicators.isTyping {
                return true
            }
        }
        return false
    }

    // MARK: -

    // Map of thread id-to-OutgoingIndicators.
    private var outgoingIndicatorsMap = [String: OutgoingIndicators]()

    private func ensureOutgoingIndicators(forThread thread: TSThread) -> OutgoingIndicators? {
        AssertIsOnMainThread()

        guard let threadId = thread.uniqueId else {
            owsFailDebug("Thread missing id")
            return nil
        }
        if let outgoingIndicators = outgoingIndicatorsMap[threadId] {
            return outgoingIndicators
        }
        let outgoingIndicators = OutgoingIndicators(delegate: self, thread: thread)
        outgoingIndicatorsMap[threadId] = outgoingIndicators
        return outgoingIndicators
    }

    // The sender maintains two timers per chat:
    //
    // A sendPause timer
    // A sendRefresh timer
    private class OutgoingIndicators {
        private weak var delegate: TypingIndicators?
        private let thread: TSThread
        private var sendPauseTimer: Timer?
        private var sendRefreshTimer: Timer?

        init(delegate: TypingIndicators, thread: TSThread) {
            self.delegate = delegate
            self.thread = thread
        }

        // MARK: - Dependencies

        private var messageSender: MessageSender {
            return SSKEnvironment.shared.messageSender
        }

        // MARK: -

        func didStartTypingOutgoingInput() {
            AssertIsOnMainThread()

            if sendRefreshTimer == nil {
                // If the user types a character into the compose box, and the sendRefresh timer isn’t running:

                // Send a ACTION=TYPING message.
                sendTypingMessageIfNecessary(forThread: thread, action: .started)
                // Start the sendRefresh timer for 10 seconds
                sendRefreshTimer?.invalidate()
                sendRefreshTimer = Timer.weakScheduledTimer(withTimeInterval: 10,
                                                            target: self,
                                                            selector: #selector(OutgoingIndicators.sendRefreshTimerDidFire),
                                                            userInfo: nil,
                                                            repeats: false)
                // Start the sendPause timer for 5 seconds
            } else {
                // If the user types a character into the compose box, and the sendRefresh timer is running:

                // Send nothing
                // Cancel the sendPause timer
                // Start the sendPause timer for 5 seconds again
            }

            sendPauseTimer?.invalidate()
            sendPauseTimer = Timer.weakScheduledTimer(withTimeInterval: 5,
                                                      target: self,
                                                      selector: #selector(OutgoingIndicators.sendPauseTimerDidFire),
                                                      userInfo: nil,
                                                      repeats: false)
        }

        func didStopTypingOutgoingInput() {
            AssertIsOnMainThread()

            // Send ACTION=STOPPED message.
            sendTypingMessageIfNecessary(forThread: thread, action: .stopped)
            // Cancel the sendRefresh timer
            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil
            // Cancel the sendPause timer
            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        @objc
        func sendPauseTimerDidFire() {
            AssertIsOnMainThread()

            // If the sendPause timer fires:

            // Send ACTION=STOPPED message.
            sendTypingMessageIfNecessary(forThread: thread, action: .stopped)
            // Cancel the sendRefresh timer
            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil
            // Cancel the sendPause timer
            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        @objc
        func sendRefreshTimerDidFire() {
            AssertIsOnMainThread()

            // If the sendRefresh timer fires:

            // Send ACTION=TYPING message
            sendTypingMessageIfNecessary(forThread: thread, action: .started)
            // Cancel the sendRefresh timer
            sendRefreshTimer?.invalidate()
            // Start the sendRefresh timer for 10 seconds again
            sendRefreshTimer = Timer.weakScheduledTimer(withTimeInterval: 10,
                                                        target: self,
                                                        selector: #selector(sendRefreshTimerDidFire),
                                                        userInfo: nil,
                                                        repeats: false)
        }

        func didSendOutgoingMessage() {
            AssertIsOnMainThread()

            // If the user sends the message:

            // Cancel the sendRefresh timer
            sendRefreshTimer?.invalidate()
            sendRefreshTimer = nil
            // Cancel the sendPause timer
            sendPauseTimer?.invalidate()
            sendPauseTimer = nil
        }

        private func sendTypingMessageIfNecessary(forThread thread: TSThread, action: TypingIndicatorAction) {
            Logger.verbose("\(TypingIndicatorMessage.string(forTypingIndicatorAction: action))")

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

            let message = TypingIndicatorMessage(thread: thread, action: action)
            messageSender.sendPromise(message: message).retainUntilComplete()
        }
    }

    // MARK: -

    // Map of (thread id and recipient id)-to-(device id)-to-IncomingIndicators.
    private var incomingIndicatorsMap = [String: [UInt: IncomingIndicators]]()

    private func incomingIndicatorsKey(forThread thread: TSThread, recipientId: String) -> String {
        return "\(String(describing: thread.uniqueId)) \(recipientId)"
    }

    private func ensureIncomingIndicators(forThread thread: TSThread, recipientId: String, deviceId: UInt) -> IncomingIndicators {
        AssertIsOnMainThread()

        let key = incomingIndicatorsKey(forThread: thread, recipientId: recipientId)
        guard let deviceMap = incomingIndicatorsMap[key] else {
            let incomingIndicators = IncomingIndicators(delegate: self, recipientId: recipientId, deviceId: deviceId)
            incomingIndicatorsMap[key] = [deviceId: incomingIndicators]
            return incomingIndicators
        }
        guard let incomingIndicators = deviceMap[deviceId] else {
            let incomingIndicators = IncomingIndicators(delegate: self, recipientId: recipientId, deviceId: deviceId)
            var deviceMapCopy = deviceMap
            deviceMapCopy[deviceId] = incomingIndicators
            incomingIndicatorsMap[key] = deviceMapCopy
            return incomingIndicators
        }
        return incomingIndicators
    }

    // The receiver maintains one timer for each (sender, device) in a chat:
    private class IncomingIndicators {
        private weak var delegate: TypingIndicators?
        private let recipientId: String
        private let deviceId: UInt
        private var displayTypingTimer: Timer?
        var isTyping = false {
            didSet {
                AssertIsOnMainThread()

                let didChange = oldValue != isTyping
                if didChange {
                    Logger.debug("isTyping changed: \(oldValue) -> \(self.isTyping)")

                    notifyIfNecessary()
                }
            }
        }

        init(delegate: TypingIndicators, recipientId: String, deviceId: UInt) {
            self.delegate = delegate
            self.recipientId = recipientId
            self.deviceId = deviceId
        }

        func didReceiveTypingStartedMessage() {
            AssertIsOnMainThread()

            // If the client receives a ACTION=TYPING message:
            //
            // Cancel the displayTyping timer for that (sender, device)
            // Display the typing indicator for that (sender, device)
            // Set the displayTyping timer for 15 seconds
            displayTypingTimer?.invalidate()
            displayTypingTimer = Timer.weakScheduledTimer(withTimeInterval: 15,
                                                          target: self,
                                                          selector: #selector(IncomingIndicators.displayTypingTimerDidFire),
                                                          userInfo: nil,
                                                          repeats: false)
            isTyping = true
        }

        func didReceiveTypingStoppedMessage() {
            AssertIsOnMainThread()

            // If the client receives a ACTION=STOPPED message:
            //
            // Cancel the displayTyping timer for that (sender, device)
            // Hide the typing indicator for that (sender, device)
            displayTypingTimer?.invalidate()
            displayTypingTimer = nil
            isTyping = false
        }

        @objc
        func displayTypingTimerDidFire() {
            AssertIsOnMainThread()

            // If the displayTyping indicator fires:
            //
            // Cancel the displayTyping timer for that (sender, device)
            // Hide the typing indicator for that (sender, device)
            displayTypingTimer?.invalidate()
            displayTypingTimer = nil
            isTyping = false
        }

        func didReceiveIncomingMessage() {
            AssertIsOnMainThread()

            // If the client receives a message:
            //
            // Cancel the displayTyping timer for that (sender, device)
            // Hide the typing indicator for that (sender, device)
            displayTypingTimer?.invalidate()
            displayTypingTimer = nil
            isTyping = false
        }

        private func notifyIfNecessary() {
            Logger.verbose("")

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

            NotificationCenter.default.postNotificationNameAsync(TypingIndicatorsImpl.typingIndicatorStateDidChange, object: recipientId)
        }
    }
}
