//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
public import SignalServiceKit

// MARK: - DecryptableProvisioningMessage

/// Protocol describing a message that can be sent and received through
/// the ProvisioningSocket.
public protocol DecryptableProvisioningMessage {

    /// Alias for the proto type that wraps the message.
    associatedtype Envelope: ProvisioningEnvelope

    init(plaintext: Data) throws
}

/// Protocol describing the envelope that contains a `DecryptableProvisioningMessage`
/// and can be sent and received through the ProvisioningSocket.
public protocol ProvisioningEnvelope {

    init(serializedData: Data) throws

    /// Encrypted payload containing the `DecryptableProvisioningMessage`
    var body: Data { get }

    /// The public key used to encrypt `bodyData`
    var publicKey: Data { get }
}

// MARK: - DecryptableProvisioningMessage conformance

extension ProvisioningProtoProvisionEnvelope: ProvisioningEnvelope {}
extension LinkingProvisioningMessage: DecryptableProvisioningMessage {
    public typealias Envelope = ProvisioningProtoProvisionEnvelope
}

extension RegistrationProvisioningEnvelope: ProvisioningEnvelope {}
extension RegistrationProvisioningMessage: DecryptableProvisioningMessage {
    public typealias Envelope = RegistrationProvisioningEnvelope
}

// MARK: - ProvisioningSocketManager

@MainActor
public protocol ProvisioningSocketManagerUIDelegate: AnyObject {
    func provisioningSocketManager(
        _ provisioningSocketManager: ProvisioningSocketManager,
        didUpdateProvisioningURL url: URL,
    )

    func provisioningSocketManagerDidPauseQRRotation(
        _ provisioningSocketManager: ProvisioningSocketManager,
    )
}

public class ProvisioningSocketManager: ProvisioningSocketDelegate {
    private struct DecryptableProvisionEnvelope {
        private let cipher: ProvisioningCipher
        private let encryptedEnvelope: Data

        init(cipher: ProvisioningCipher, data: Data) {
            self.cipher = cipher
            self.encryptedEnvelope = data
        }

        func decrypt<ProvisioningMessage: DecryptableProvisioningMessage>() throws -> ProvisioningMessage {
            let envelope = try ProvisioningMessage.Envelope(serializedData: encryptedEnvelope)
            let data = try cipher.decrypt(data: envelope.body, theirPublicKey: try PublicKey(envelope.publicKey))
            return try ProvisioningMessage(plaintext: data)
        }
    }

    /// Represents an attempt to communicate with the primary.
    private struct ProvisioningCommunicationAttempt {
        /// The socket from which we hope to receive a provisioning envelope
        /// from a primary.
        let socket: ProvisioningSocket
        /// The cipher to be used in encrypting the provisioning envelope.
        let cipher: ProvisioningCipher
        /// A continuation waiting for us to fetch the address necessary for
        /// us to construct a provisioning URL, which we will present to the
        /// primary via QR code. The provisioning URL will contain the necessary
        /// data for the primary to send us a provisioning envelope over our
        /// provisioning socket, via the server.
        var fetchProvisioningAddressContinuation: CheckedContinuation<String, Error>?
    }

    private let activeCommunicationAttempts = AtomicValue<[ObjectIdentifier: ProvisioningCommunicationAttempt]>([:], lock: .init())

    private var awaitProvisionEnvelopeContinuation: AtomicValue<CheckedContinuation<DecryptableProvisionEnvelope, Error>?> = AtomicValue(nil, lock: .init())

    public var delegate: ProvisioningSocketManagerUIDelegate?

    private let linkType: DeviceProvisioningURL.LinkType
    public init(linkType: DeviceProvisioningURL.LinkType) {
        self.linkType = linkType
    }

    // Start:
    // rotate the sockets.  Call back to delegate when the socket updates
    // Call back whit
    public func start() {
        rotate()
    }

    public func reset() {
        stop()
        start()
    }

    public func stop() {
        rotationTask?.cancel()
        rotationTask = nil
    }

    // MARK: ProvisioningSocketDelegate

    public func provisioningSocket(
        _ provisioningSocket: ProvisioningSocket,
        didReceiveProvisioningUuid provisioningAddress: String,
    ) {
        let continuation = self.activeCommunicationAttempts.update {
            var communicationAttempt = $0.removeValue(forKey: ObjectIdentifier(provisioningSocket))
            owsAssertDebug(communicationAttempt != nil)
            let continuation = communicationAttempt?.fetchProvisioningAddressContinuation.take()
            $0[ObjectIdentifier(provisioningSocket)] = communicationAttempt
            return continuation
        }
        continuation?.resume(returning: provisioningAddress)
    }

    public func provisioningSocket(
        _ provisioningSocket: ProvisioningSocket,
        didReceiveEnvelopeData data: Data,
    ) {
        let activeCommunicationAttempts = self.activeCommunicationAttempts.get()

        guard let fulfilledCommunicationAttempt = activeCommunicationAttempts[ObjectIdentifier(provisioningSocket)] else {
            owsFailDebug("invalid socket")
            return
        }
        /// We've gotten a provisioning message, from one of our attempts'
        /// sockets. (We don't care which one – it's whichever one the primary
        /// scanned and sent an envelope through!)

        /// After we get a provisioning message, we don't expect anything
        /// from this or any other socket.
        for (_, obsoleteCommunicationAttempt) in activeCommunicationAttempts {
            obsoleteCommunicationAttempt.socket.disconnect(code: .normalClosure)
        }

        awaitProvisionEnvelopeContinuation.update { existingContinuation in
            guard let continuation = existingContinuation else {
                owsFailDebug("Got provision envelope, but missing continuation or cipher!")
                return
            }

            stop()
            let envelope = DecryptableProvisionEnvelope(cipher: fulfilledCommunicationAttempt.cipher, data: data)
            continuation.resume(returning: envelope)

            existingContinuation = nil
        }
    }

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error) {
        if
            let webSocketError = error as? WebSocketError,
            case .closeError = webSocketError
        {
            Logger.info("Provisioning socket closed...")
        } else {
            Logger.error("\(error)")
        }

        // Remove the socket from the list of active sockets -- we're done with it.
        let communicationAttempt = self.activeCommunicationAttempts.update {
            return $0.removeValue(forKey: ObjectIdentifier(provisioningSocket))
        }
        owsAssertDebug(communicationAttempt != nil)
        // Throw the error via the continuation to avoid stalling if anything is waiting.
        communicationAttempt?.fetchProvisioningAddressContinuation?.resume(throwing: error)
    }

    // MARK: -

    private static func buildProvisioningUrl(
        type: DeviceProvisioningURL.LinkType,
        address: String,
        publicKey: PublicKey,
    ) throws -> URL {

        let shouldLinkAndSync: Bool = {
            switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
            case .unregistered:
                return true
            case .delinked, .relinking:
                // We don't allow relinking secondaries to link'n'sync.
                return false
            case .transferred:
                // Transferring back to a transfered device will result in hitting this.
                return false
            case
                .registered,
                .provisioned,
                .reregistering,
                .transferringIncoming,
                .transferringLinkedOutgoing,
                .transferringPrimaryOutgoing,
                .deregistered:
                owsFailDebug("How are we provisioning from this state?")
                return false
            }
        }()

        var capabilities = [DeviceProvisioningURL.Capability]()
        if shouldLinkAndSync {
            capabilities.append(DeviceProvisioningURL.Capability.linknsync)
        }

        return try DeviceProvisioningURL(
            type: type,
            ephemeralDeviceId: address,
            publicKey: publicKey,
            capabilities: capabilities,
        ).buildUrl()
    }

    /// Opens a new provisioning socket. Note that the server closes
    /// provisioning sockets after 90s, so callers must ensure that they do not
    /// need the socket longer than that.
    ///
    /// - Returns
    /// A provisioning URL containing information about the now-opened
    /// provisioning socket.
    func openNewProvisioningSocket() async throws -> URL {
        let ourKeyPair = IdentityKeyPair.generate()
        let cipher = ProvisioningCipher(ourKeyPair: ourKeyPair)

        let provisioningAddress: String = try await withCheckedThrowingContinuation { continuation in
            let socket = ProvisioningSocket()
            let newAttempt = ProvisioningCommunicationAttempt(
                socket: socket,
                cipher: cipher,
                fetchProvisioningAddressContinuation: continuation,
            )

            self.activeCommunicationAttempts.update { $0[ObjectIdentifier(socket)] = newAttempt }

            newAttempt.socket.delegate = self
            newAttempt.socket.connect()
        }

        return try Self.buildProvisioningUrl(
            type: linkType,
            address: provisioningAddress,
            publicKey: ourKeyPair.publicKey,
        )
    }

    public func waitForMessage<ProvisioningMessage: DecryptableProvisioningMessage>() async throws -> ProvisioningMessage {
        let decryptableProvisionEnvelope: DecryptableProvisionEnvelope = try await withCheckedThrowingContinuation { newContinuation in
            awaitProvisionEnvelopeContinuation.update { existingContinuation in
                guard existingContinuation == nil else {
                    newContinuation.resume(throwing: OWSAssertionError("Attempted to await provisioning multiple times!"))
                    return
                }
                existingContinuation = newContinuation
            }
        }
        return try decryptableProvisionEnvelope.decrypt()
    }

    private var rotationTask: Task<Void, Never>?
    private func rotate() {
        rotationTask?.cancel()
        rotationTask = Task {
            /// Every 45s, five times, rotate the provisioning socket for which
            /// we're displaying a QR code. If we fail, or once we've exhausted
            /// the five rotations, fall back to showing a manual "refresh"
            /// button.
            ///
            /// Note that the server will close provisioning sockets after 90s,
            /// so hopefully rotating every 45s means no primary will ever end
            /// up trying to send into a closed socket.
            do {
                for _ in 0..<5 {
                    let provisioningUrl = try await self.openNewProvisioningSocket()

                    try Task.checkCancellation()

                    await delegate?.provisioningSocketManager(self, didUpdateProvisioningURL: provisioningUrl)

                    try await Task.sleep(nanoseconds: 45 * NSEC_PER_SEC)

                    try Task.checkCancellation()
                }
                await delegate?.provisioningSocketManagerDidPauseQRRotation(self)
            } catch is CancellationError {
                // We've been canceled; bail! It's the canceler's responsibility
                // to make sure the UI is updated.
                return
            } catch {
                // Fall through as if we'd exhausted our rotations.
            }
        }
    }
}
