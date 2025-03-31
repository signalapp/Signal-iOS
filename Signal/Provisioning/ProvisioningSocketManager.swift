//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import LibSignalClient

@MainActor
public protocol ProvisioningSocketManagerUIDelegate: AnyObject {
    func provisioningSocketManager(_ provisioningSocketManager: ProvisioningSocketManager, didUpdateProvisioningURL url: URL)
    func provisioningSocketManagerDidPauseQRRotation(_ provisioningSocketManager: ProvisioningSocketManager)
}

public class ProvisioningSocketManager: ProvisioningSocketDelegate {
    private struct ProvisioningUrlParams {
        let uuid: String
        let cipher: ProvisioningCipher
    }

    private struct DecryptableProvisionEnvelope {
        let cipher: ProvisioningCipher
        let envelope: ProvisioningProtoProvisionEnvelope

        init(cipher: ProvisioningCipher, data: Data) throws {
            self.cipher = cipher
            self.envelope = try ProvisioningProtoProvisionEnvelope(serializedData: data)
        }

        func decrypt() throws -> ProvisioningMessage {
            let data = try cipher.decrypt(data: envelope.body, theirPublicKey: try PublicKey(envelope.publicKey))
            return try ProvisioningMessage(plaintext: data)
        }
    }

    /// Represents an attempt to communicate with the primary.
    private struct ProvisioningUrlCommunicationAttempt {
        /// The socket from which we hope to receive a provisioning envelope
        /// from a primary.
        let socket: ProvisioningSocket
        /// The cipher to be used in encrypting the provisioning envelope.
        let cipher: ProvisioningCipher
        /// A continuation waiting for us to fetch the parameters necessary for
        /// us to construct a provisioning URL, which we will present to the
        /// primary via QR code. The provisioning URL will contain the necessary
        /// data for the primary to send us a provisioning envelope over our
        /// provisioning socket, via the server.
        var fetchProvisioningUrlParamsContinuation: CheckedContinuation<ProvisioningUrlParams, Error>?
    }

    private var urlCommunicationAttempts: AtomicValue<[ProvisioningUrlCommunicationAttempt]> = AtomicValue([], lock: .init())
    private var awaitProvisionEnvelopeContinuation: AtomicValue<CheckedContinuation<DecryptableProvisionEnvelope?, Never>?> = AtomicValue(nil, lock: .init())

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

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveProvisioningUuid provisioningUuid: String) {
        urlCommunicationAttempts.update { attempts in
            let matchingAttemptIndex = attempts.firstIndex {
                $0.socket.id == provisioningSocket.id
            }

            guard
                let matchingAttemptIndex,
                let fetchParamsContinuation = attempts[matchingAttemptIndex].fetchProvisioningUrlParamsContinuation
            else {
                owsFailDebug("Got provisioning UUID for unknown socket!")
                return
            }

            attempts[matchingAttemptIndex].fetchProvisioningUrlParamsContinuation = nil

            fetchParamsContinuation.resume(
                returning: ProvisioningUrlParams(
                    uuid: provisioningUuid,
                    cipher: attempts[matchingAttemptIndex].cipher
                )
            )
        }
    }

    public func provisioningSocket(
        _ provisioningSocket: ProvisioningSocket,
        didReceiveEnvelopeData data: Data
    ) {
        var cipherForSocket: ProvisioningCipher?

        /// We've gotten a provisioning message, from one of our attempts'
        /// sockets. (We don't care which one – it's whichever one the primary
        /// scanned and sent an envelope through!)
        for attempt in urlCommunicationAttempts.get() {
            /// After we get a provisioning message, we don't expect anything
            /// from this or any other socket.
            attempt.socket.disconnect(code: .normalClosure)

            if provisioningSocket.id == attempt.socket.id {
                owsAssertDebug(
                    cipherForSocket == nil,
                    "Extracting cipher, but unexpectedly already set from previous match!"
                )

                cipherForSocket = attempt.cipher
            }
        }

        guard let cipherForSocket else {
            owsFailDebug("Missing cipher for socket that received envelope!")
            return
        }

        awaitProvisionEnvelopeContinuation.update { continuation in
            guard let continuation else {
                owsFailDebug("Got provision envelope, but missing continuation or cipher!")
                return
            }

            do {
                let envelope = try DecryptableProvisionEnvelope(
                    cipher: cipherForSocket,
                    data: data
                )
                continuation.resume(returning: envelope)
            } catch {
                owsFailDebug("Failed to decrypt provision envelope!")
                continuation.resume(returning: nil)
            }
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

        urlCommunicationAttempts.update { attempts in
            let matchingAttemptIndex = attempts.firstIndex {
                $0.socket.id == provisioningSocket.id
            }

            guard let matchingAttemptIndex else {
                owsFailDebug("Got provisioning UUID for unknown socket!")
                return
            }

            attempts[matchingAttemptIndex].fetchProvisioningUrlParamsContinuation?.resume(throwing: error)
            attempts[matchingAttemptIndex].fetchProvisioningUrlParamsContinuation = nil
        }
    }

    // MARK: -

    private static func buildProvisioningUrl(
        type: DeviceProvisioningURL.LinkType,
        params: ProvisioningUrlParams
    ) throws -> URL {

        let shouldLinkAndSync: Bool = {
            switch DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction {
            case .unregistered:
                return FeatureFlags.linkAndSyncLinkedImport
            case .delinked, .relinking:
                // We don't allow relinking secondaries to link'n'sync.
                return false
            case
                .registered,
                .provisioned,
                .reregistering,
                .transferred,
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
            ephemeralDeviceId: params.uuid,
            publicKey: params.cipher.ourPublicKey,
            capabilities: capabilities
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
        let provisioningUrlParams: ProvisioningUrlParams = try await withCheckedThrowingContinuation { paramsContinuation in
            let newAttempt = ProvisioningUrlCommunicationAttempt(
                socket: ProvisioningSocket(),
                cipher: ProvisioningCipher(),
                fetchProvisioningUrlParamsContinuation: paramsContinuation
            )

            urlCommunicationAttempts.update { $0.append(newAttempt) }

            newAttempt.socket.delegate = self
            newAttempt.socket.connect()
        }

        return try Self.buildProvisioningUrl(type: linkType, params: provisioningUrlParams)
    }

    public func waitForMessage() async throws -> ProvisioningMessage {
        let decryptableProvisionEnvelope: DecryptableProvisionEnvelope? = await withCheckedContinuation { newContinuation in
            awaitProvisionEnvelopeContinuation.update { existingContinuation in
                guard existingContinuation == nil else {
                    newContinuation.resume(returning: nil)
                    return
                }

                existingContinuation = newContinuation
            }
        }
        guard let decryptableProvisionEnvelope else {
            // TODO: Throw real error
            throw OWSAssertionError("Attempted to await provisioning multiple times!")
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

                    let rotationDelaySecs: UInt64
#if TESTABLE_BUILD
                    rotationDelaySecs = 3
#else
                    rotationDelaySecs = 45
#endif

                    try await Task.sleep(nanoseconds: rotationDelaySecs * NSEC_PER_SEC)

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
