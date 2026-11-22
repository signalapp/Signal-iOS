//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation
public import LibSignalClient

public class WebAuthn {

    private enum Constants {
        static let credentialDomain = "login.signal.org"
        static let challengeByteLength: UInt = 32
    }

    struct PasskeyRegistration {
        let attestationObject: Data
        let clientDataJSON: Data
    }

    private let accountEntropyPool: AccountEntropyPool
    private let dateProvider: DateProvider
    private let serviceProvider: ServiceProvider

    public init(
        accountEntropyPool: AccountEntropyPool,
        dateProvider: @escaping DateProvider,
        serviceProvider: ServiceProvider,
    ) {
        self.accountEntropyPool = accountEntropyPool
        self.dateProvider = dateProvider
        self.serviceProvider = serviceProvider
    }

    @MainActor
    public func setup() async throws -> ConfirmedMfaKey {
        let params = try await serviceProvider.withAuthService(.accounts) {
            try await $0.startWebAuthnRegistration()
        }
        let identifier = Constants.credentialDomain
        let challenge = Randomness.generateRandomBytes(Constants.challengeByteLength)
        let label = dateProvider().formatted(
            Date.ISO8601FormatStyle(timeZone: .current).year().month().day(),
        )

        // Biometric auth based passkey
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: identifier)
        let platformRequest = platformProvider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: label,
            userID: params.userHandle,
        )
        platformRequest.attestationPreference = .none

        // Security key based passkey
        let keyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: identifier)
        let keyRequest = keyProvider.createCredentialRegistrationRequest(
            challenge: challenge,
            displayName: label,
            name: label,
            userID: params.userHandle,
        )
        keyRequest.credentialParameters = params.allowedAlgorithms.map {
            ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier(Int($0)))
        }
        keyRequest.attestationPreference = .none

        let controller = ASAuthorizationController(authorizationRequests: [platformRequest, keyRequest])
        let authorization = try await RegistrationControllerWrapper(controller: controller).performRequests()

        guard let json = String(data: authorization.clientDataJSON, encoding: .utf8) else {
            throw OWSAssertionError("Invalid clientDataJSON")
        }
        let mfaMetadata = MfaMetadata(name: label, createdAt: dateProvider())

        let id = try await serviceProvider.withAuthService(.accounts) {
            try await $0.finishWebAuthnRegistration(
                attestationObject: authorization.attestationObject,
                collectedClientDataJson: json,
                metadata: mfaMetadata,
                svrKey: accountEntropyPool.getMasterKey().asSvrKey,
            )
        }

        return ConfirmedMfaKey(
            id: id,
            metadata: mfaMetadata,
            kind: .webAuthn,
        )
    }

    @MainActor
    public static func authenticate(parameters: WebAuthnAuthenticationParameters) async throws -> String {
        let identifier = Constants.credentialDomain

        // Biometric auth based passkey
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: identifier)
        let platformRequest = platformProvider.createCredentialAssertionRequest(challenge: parameters.challenge)
        platformRequest.allowedCredentials = parameters.allowedCredentialIds.map {
            return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }

        // Security key based passkey
        let keyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: identifier)
        let keyRequest = keyProvider.createCredentialAssertionRequest(challenge: parameters.challenge)
        keyRequest.allowedCredentials = parameters.allowedCredentialIds.map {
            ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                credentialID: $0,
                transports: ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported,
            )
        }

        let controller = ASAuthorizationController(authorizationRequests: [platformRequest, keyRequest])
        return try await AssertionControllerWrapper(controller: controller).performRequests()
    }

    // MARK: - Delegate Wrappers

    @MainActor
    private class AssertionControllerWrapper: NSObject, ASAuthorizationControllerDelegate {

        private var continuation: CheckedContinuation<String, Error>?
        private let controller: ASAuthorizationController

        init(controller: ASAuthorizationController) {
            self.controller = controller
        }

        func performRequests() async throws -> String {
            controller.delegate = self
            return try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self else { return }
                self.continuation = continuation
                controller.performRequests()
            }
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization,
        ) {
            guard let authorization = authorization.credential as? ASAuthorizationPublicKeyCredentialAssertion else {
                continuation.take()?.resume(throwing: ASAuthorizationError(.failed))
                return
            }

            // Build up a response following this: https://www.w3.org/TR/webauthn/#dom-publickeycredential-tojson
            var response: [String: Any] = [
                "clientDataJSON": authorization.rawClientDataJSON.asBase64Url,
                "authenticatorData": authorization.rawAuthenticatorData.asBase64Url,
                "signature": authorization.signature.asBase64Url,
            ]

            if
                let userID = authorization.userID,
                !userID.isEmpty
            {
                response["userHandle"] = userID.asBase64Url
            }

            let json: [String: Any] = [
                "id": authorization.credentialID.asBase64Url,
                "rawId": authorization.credentialID.asBase64Url,
                "type": "public-key",
                "response": response,
                "clientExtensionResults": [:],
            ]

            do {
                let data = try JSONSerialization.data(withJSONObject: json)
                if let string = String(data: data, encoding: .utf8) {
                    continuation.take()?.resume(returning: string)
                } else {
                    continuation.take()?.resume(throwing: OWSAssertionError("Invalid data"))
                }
            } catch {
                continuation.take()?.resume(throwing: error)
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            continuation.take()?.resume(throwing: error)
        }
    }

    @MainActor
    private class RegistrationControllerWrapper: NSObject, ASAuthorizationControllerDelegate {
        private var continuation: CheckedContinuation<PasskeyRegistration, Error>?
        private let controller: ASAuthorizationController

        init(controller: ASAuthorizationController) {
            self.controller = controller
        }

        func performRequests() async throws -> PasskeyRegistration {
            controller.delegate = self
            return try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self else { return }
                self.continuation = continuation
                controller.performRequests()
            }
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization,
        ) {
            // Check if the registration is one of the types we support (passkey, security key)
            let registration: ASAuthorizationPublicKeyCredentialRegistration
            switch authorization.credential {
            case let reg as ASAuthorizationPlatformPublicKeyCredentialRegistration:
                registration = reg
            case let reg as ASAuthorizationSecurityKeyPublicKeyCredentialRegistration:
                registration = reg
            default:
                continuation.take()?.resume(throwing: OWSAssertionError("unexpectedCredentialType"))
                return
            }

            // Return the registration data needed by libsignal
            if let attestation = registration.rawAttestationObject {
                continuation.take()?.resume(returning: PasskeyRegistration(
                    attestationObject: attestation,
                    clientDataJSON: registration.rawClientDataJSON,
                ))
            } else {
                continuation.take()?.resume(throwing: OWSAssertionError("missingAttestation"))
            }
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: any Error,
        ) {
            continuation.take()?.resume(throwing: error)
        }
    }
}
