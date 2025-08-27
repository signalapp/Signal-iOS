//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol RegistrationWebSocketManager {
    /// Allows the web socket to open to service registration requests.
    ///
    /// We've completed enough registration to have an auth token, so open a web
    /// socket & allow requests that explicitly specify that auth token.
    @MainActor
    func acquireRestrictedWebSocket(chatServiceAuth: ChatServiceAuth) async

    /// Removes the registration restriction from the web socket.
    ///
    /// Callers should ensure that a normal web socket is allowed before calling
    /// this method. (They are allowed when registered/provisioned.)
    ///
    /// - Parameter isRegistered: If false, any messages received on the
    /// restricted web socket will be discarded. If true, those messages will be
    /// kept and processed as soon as message processing is unsuspended.
    @MainActor
    func releaseRestrictedWebSocket(isRegistered: Bool) async
}

struct RegistrationWebSocketManagerImpl: RegistrationWebSocketManager {
    enum Shims {
        typealias MessagePipelineSupervisor = _RegistrationWebSocketManager_MessagePipelineSupervisorShim
        typealias MessageProcessor = _RegistrationWebSocketManager_MessageProcessorShim
    }

    private let chatConnectionManager: any ChatConnectionManager
    private let messagePipelineSupervisor: any Shims.MessagePipelineSupervisor
    private let messageProcessor: any Shims.MessageProcessor

    init(
        chatConnectionManager: any ChatConnectionManager,
        messagePipelineSupervisor: any Shims.MessagePipelineSupervisor,
        messageProcessor: any Shims.MessageProcessor,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.messageProcessor = messageProcessor
    }

    @MainActor
    func acquireRestrictedWebSocket(chatServiceAuth: ChatServiceAuth) async {
        Logger.info("")

        // We want to open a socket, but we don't want to process messages yet, so
        // suspend processing until we've finished registration.
        messagePipelineSupervisor.suspendMessageProcessingWithoutHandle(for: .registrationProvisioning)

        await chatConnectionManager.setRegistrationOverride(chatServiceAuth)
    }

    @MainActor
    func releaseRestrictedWebSocket(isRegistered: Bool) async {
        Logger.info("")

        // Jump through the main queue to ensure we lose the race with the
        // registrationStateDidChange notification. This avoids a race condition
        // that may cause the socket to cycle inadvertently.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        // Remove the override; this may be a no-op (if we are now fully registered
        // and can keep the socket open without an override) or it may disconnect
        // the socket (if we encountered an error when registering).
        await chatConnectionManager.clearRegistrationOverride()

        // If we hit an error and aren't registered, we want to drop any messages
        // we've received but not yet processed. When using REST, we never would
        // have fetched these messages, and dropping them mimics that behavior.
        if !isRegistered {
            await withCheckedContinuation { continuation in
                // Make sure we've enqueued all of them.
                messageProcessor.flushEnqueuingQueue {
                    // And then drop everything that's enqueued.
                    messageProcessor.dropEnqueuedEnvelopes {
                        continuation.resume()
                    }
                }
            }
        }

        // It's now safe to resume message processing. Either (a) we're registered,
        // and we can process everything waiting in the queue, or (b) we're not
        // registered, and we just dropped everything in the queue.
        messagePipelineSupervisor.unsuspendMessageProcessing(for: .registrationProvisioning)
    }
}

// MARK: -

protocol _RegistrationWebSocketManager_MessageProcessorShim {
    func flushEnqueuingQueue(completion: @escaping () -> Void)
    func dropEnqueuedEnvelopes(completion: @escaping () -> Void)
}

extension MessageProcessor: _RegistrationWebSocketManager_MessageProcessorShim {
}

protocol _RegistrationWebSocketManager_MessagePipelineSupervisorShim {
    func suspendMessageProcessingWithoutHandle(for suspension: MessagePipelineSupervisor.Suspension)
    func unsuspendMessageProcessing(for suspension: MessagePipelineSupervisor.Suspension)
}

extension MessagePipelineSupervisor: _RegistrationWebSocketManager_MessagePipelineSupervisorShim {
}

// MARK: -

#if TESTABLE_BUILD

struct MockRegistrationWebSocketManager: RegistrationWebSocketManager {
    func acquireRestrictedWebSocket(chatServiceAuth: ChatServiceAuth) async {}
    func releaseRestrictedWebSocket(isRegistered: Bool) async {}
}

#endif
