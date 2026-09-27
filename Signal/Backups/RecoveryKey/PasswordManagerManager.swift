//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import SignalServiceKit

/// Responsible for interactions with the system password manager, via
/// `AuthenticationServices`.
///
/// - Note
/// An `NSObject` subclass because of `@objc` protocols.
class PasswordManagerManager:
    NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private struct State {
        var continuations: [ObjectIdentifier: CheckedContinuation<DisplayableAccountEntropyPool, Error>] = [:]
    }

    private let tsAccountManager: TSAccountManager

    private let state: AtomicValue<State>

    init(
        tsAccountManager: TSAccountManager,
    ) {
        self.tsAccountManager = tsAccountManager

        self.state = AtomicValue(State(), lock: .init())
    }

    private var window: UIWindow {
        CurrentAppContext().mainWindow.owsFailUnwrap("Missing window!")
    }

    // MARK: -

    @available(iOS 26.2, *)
    func saveDisplayableAEP(_ displayableAEP: DisplayableAccountEntropyPool) async throws {
        let registeredState: RegisteredState
        do throws(NotRegisteredError) {
            registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
        } catch {
            Logger.warn("Cannot save to password manager while unregistered!")
            throw error
        }

        let credentialDataManager = ASCredentialDataManager()
        let password = ASPasswordCredential(
            user: registeredState.localIdentifiers.aci.serviceIdUppercaseString,
            password: displayableAEP.displayString,
        )
        let scope = ASAutoFillURLScope(host: "signal.org")

        do {
            try await credentialDataManager.save(
                password: password,
                for: scope,
                title: OWSLocalizedString(
                    "PASSWORD_MANAGER_SIGNAL_APP_NAME",
                    comment: "The name of the Signal app, used as the title for an entry in a user's password manager for their Signal Recovery Key. Should be localized with the same value as the app's name in the iOS App Store.",
                ),
                anchor: window,
            )
        } catch {
            Logger.warn("Failed to save to password manager! \(error)")
            throw error
        }
    }

    // MARK: -

    func requestDisplayableAEP() async throws -> DisplayableAccountEntropyPool {
        try await withCheckedThrowingContinuation { continutation in
            let request = ASAuthorizationPasswordProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self

            state.update {
                $0.continuations[ObjectIdentifier(controller)] = continutation
                controller.performRequests()
            }
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    @objc(authorizationController:didCompleteWithAuthorization:)
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization,
    ) {
        guard
            let continuation = state.update(block: {
                $0.continuations.removeValue(forKey: ObjectIdentifier(controller))
            })
        else {
            owsFailDebug("Missing continuation for controller for which we are the delegate?")
            return
        }

        guard
            let credential = authorization.credential as? ASPasswordCredential
        else {
            Logger.warn("Missing password credential")
            continuation.resume(throwing: OWSGenericError("Missing password credential!"))
            return
        }

        do {
            let displayableAEP = try DisplayableAccountEntropyPool(displayString: credential.password)
            return continuation.resume(returning: displayableAEP)
        } catch let error {
            Logger.warn("Password was not valid DisplayableAEP! \(error)")
            continuation.resume(throwing: error)
            return
        }
    }

    @objc(authorizationController:didCompleteWithError:)
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error,
    ) {
        guard
            let continuation = state.update(block: {
                $0.continuations.removeValue(forKey: ObjectIdentifier(controller))
            })
        else {
            owsFailDebug("Missing continuation for controller for which we are the delegate?")
            return
        }

        Logger.warn("ASAuthorizationController failure: \(error)")
        continuation.resume(throwing: error)
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return window
    }
}
