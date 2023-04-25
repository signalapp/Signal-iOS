//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

@objc
public class Deprecated_ProvisioningController: NSObject {

    let onboardingController: Deprecated_OnboardingController

    private let provisioningCipher: ProvisioningCipher
    private let provisioningSocket: ProvisioningSocket

    private var deviceIdPromise: Promise<String>
    private var deviceIdFuture: Future<String>

    private var provisionEnvelopePromise: Promise<ProvisioningProtoProvisionEnvelope>
    private var provisionEnvelopeFuture: Future<ProvisioningProtoProvisionEnvelope>

    public init(onboardingController: Deprecated_OnboardingController) {
        self.onboardingController = onboardingController
        provisioningCipher = ProvisioningCipher.generate()

        (self.deviceIdPromise, self.deviceIdFuture) = Promise.pending()
        (self.provisionEnvelopePromise, self.provisionEnvelopeFuture) = Promise.pending()

        provisioningSocket = ProvisioningSocket()

        super.init()

        provisioningSocket.delegate = self
    }

    public func resetPromises() {
        _awaitProvisionMessage = nil
        (self.deviceIdPromise, self.deviceIdFuture) = Promise.pending()
        (self.provisionEnvelopePromise, self.provisionEnvelopeFuture) = Promise.pending()
    }

    @objc
    public static func presentRelinkingFlow() {
        // TODO[ViewContextPiping]
        let context = ViewControllerContext.shared
        let onboardingController = Deprecated_OnboardingController(context: context, onboardingMode: .provisioning)
        let navController = Deprecated_OnboardingNavigationController(onboardingController: onboardingController)

        let provisioningController = Deprecated_ProvisioningController(onboardingController: onboardingController)
        let vc = Deprecated_SecondaryLinkingQRCodeViewController(provisioningController: provisioningController)
        navController.setViewControllers([vc], animated: false)

        provisioningController.awaitProvisioning(from: vc, navigationController: navController)
        CurrentAppContext().mainWindow?.rootViewController = navController
    }

    // MARK: -

    func didConfirmSecondaryDevice(from viewController: Deprecated_SecondaryLinkingPrepViewController) {
        guard let navigationController = viewController.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        let qrCodeViewController = Deprecated_SecondaryLinkingQRCodeViewController(provisioningController: self)
        navigationController.pushViewController(qrCodeViewController, animated: true)

        awaitProvisioning(from: qrCodeViewController, navigationController: navigationController)
    }

    private func awaitProvisioning(from viewController: Deprecated_SecondaryLinkingQRCodeViewController,
                                   navigationController: UINavigationController) {

        awaitProvisionMessage.done { [weak self, weak navigationController] message in
            guard let self = self else { throw PromiseError.cancelled }
            guard let navigationController = navigationController else { throw PromiseError.cancelled }

            // Verify the primary device is new enough to link us. Right now this is a simple check
            // of >= the latest version, but when we bump the version we may need to be more specific
            // if we have some backwards compatible support and allow a limited linking with an old
            // version of the app.
            guard let provisioningVersion = message.provisioningVersion,
                provisioningVersion >= OWSDeviceProvisionerConstant.provisioningVersion else {
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString("SECONDARY_LINKING_ERROR_OLD_VERSION_TITLE",
                                                 comment: "alert title for outdated linking device"),
                        message: OWSLocalizedString("SECONDARY_LINKING_ERROR_OLD_VERSION_MESSAGE",
                                                   comment: "alert message for outdated linking device")
                    ) { _ in
                        self.resetPromises()
                        navigationController.popViewController(animated: true)
                    }
                return
            }

            let confirmVC = Deprecated_SecondaryLinkingSetDeviceNameViewController(provisioningController: self)
            navigationController.pushViewController(confirmVC, animated: true)
        }.catch { error in
            switch error {
            case PromiseError.cancelled:
                Logger.info("cancelled")
            default:
                Logger.warn("error: \(error)")
                let alert = ActionSheetController(title: OWSLocalizedString("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN", comment: "alert title"),
                                                  message: error.userErrorDescription)
                alert.addAction(ActionSheetAction(title: CommonStrings.retryButton,
                                                  accessibilityIdentifier: "alert.retry",
                                                  style: .default,
                                                  handler: { _ in
                                                    self.resetPromises()
                                                    navigationController.popViewController(animated: true)
                }))
                navigationController.presentActionSheet(alert)
            }
        }
    }

    func didSetDeviceName(_ deviceName: String, from viewController: UIViewController) {
        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            self.completeLinking(deviceName: deviceName).done {
                modal.dismiss {
                    self.onboardingController.linkingDidComplete(from: viewController)
                }
            }.catch { error in
                Logger.warn("error: \(error)")

                let alert: ActionSheetController
                switch error {
                case AccountManagerError.reregistrationDifferentAccount:
                    let title = OWSLocalizedString("SECONDARY_LINKING_ERROR_DIFFERENT_ACCOUNT_TITLE",
                                                  comment: "Title for error alert indicating that re-linking failed because the account did not match.")
                    let message = OWSLocalizedString("SECONDARY_LINKING_ERROR_DIFFERENT_ACCOUNT_MESSAGE",
                                                    comment: "Message for error alert indicating that re-linking failed because the account did not match.")
                    alert = ActionSheetController(title: title, message: message)
                    alert.addAction(ActionSheetAction(title: OWSLocalizedString("SECONDARY_LINKING_ERROR_DIFFERENT_ACCOUNT_RESET_DEVICE",
                                                                               comment: "Label for the 'reset device' action in the 're-linking failed because the account did not match' alert."),
                                                      accessibilityIdentifier: "alert.reset_device",
                                                      style: .default,
                                                      handler: { _ in
                                                        Self.resetDeviceState()
                                                      }))
                case SignalServiceError.obsoleteLinkedDevice:
                    let title = OWSLocalizedString("SECONDARY_LINKING_ERROR_OBSOLETE_LINKED_DEVICE_TITLE",
                                                  comment: "Title for error alert indicating that a linked device must be upgraded before it can be linked.")
                    let message = OWSLocalizedString("SECONDARY_LINKING_ERROR_OBSOLETE_LINKED_DEVICE_MESSAGE",
                                                    comment: "Message for error alert indicating that a linked device must be upgraded before it can be linked.")
                    alert = ActionSheetController(title: title, message: message)

                    let updateButtonText = OWSLocalizedString("APP_UPDATE_NAG_ALERT_UPDATE_BUTTON", comment: "Label for the 'update' button in the 'new app version available' alert.")
                    let updateAction = ActionSheetAction(title: updateButtonText,
                                                         accessibilityIdentifier: "alert.update",
                                                         style: .default) { _ in
                                                            let url = TSConstants.appStoreUrl
                                                            UIApplication.shared.open(url, options: [:])
                    }
                    alert.addAction(updateAction)
                case let error as DeviceLimitExceededError:
                    alert = ActionSheetController(title: error.errorDescription, message: error.recoverySuggestion)
                    alert.addAction(ActionSheetAction(title: CommonStrings.okButton))
                default:
                    let title = OWSLocalizedString("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN", comment: "alert title")
                    let message = error.userErrorDescription
                    alert = ActionSheetController(title: title, message: message)
                    alert.addAction(ActionSheetAction(title: CommonStrings.retryButton,
                                                      accessibilityIdentifier: "alert.retry",
                                                      style: .default,
                                                      handler: { _ in
                                                        self.didSetDeviceName(deviceName, from: viewController)
                    }))
                }
                modal.dismiss {
                    viewController.presentActionSheet(alert)
                }
            }
        }

        ModalActivityIndicatorViewController.present(fromViewController: viewController,
                                                     canCancel: false,
                                                     backgroundBlock: backgroundBlock)
    }

    private static func resetDeviceState() {
        Logger.warn("")

        SignalApp.resetAppDataWithUI()
    }

    public func getProvisioningURL() -> Promise<URL> {
        return getDeviceId().map { [weak self] deviceId in
            guard let self = self else { throw PromiseError.cancelled }

            return try self.buildProvisioningUrl(deviceId: deviceId)
        }
    }

    private var _awaitProvisionMessage: Promise<ProvisionMessage>?
    private var awaitProvisionMessage: Promise<ProvisionMessage> {
        if _awaitProvisionMessage == nil {
            _awaitProvisionMessage = provisionEnvelopePromise.map { [weak self] envelope in
                guard let self = self else { throw PromiseError.cancelled }
                return try self.provisioningCipher.decrypt(envelope: envelope)
            }
        }
        return _awaitProvisionMessage!
    }

    private func completeLinking(deviceName: String) -> Promise<Void> {
        return awaitProvisionMessage.then { [weak self] provisionMessage -> Promise<Void> in
            guard let self = self else { throw PromiseError.cancelled }

            return self.accountManager.completeSecondaryLinking(provisionMessage: provisionMessage,
                                                                deviceName: deviceName)
        }
    }

    // MARK: -

    private func buildProvisioningUrl(deviceId: String) throws -> URL {
        let base64PubKey: String = provisioningCipher
            .secondaryDevicePublicKey
            .serialized
            .base64EncodedString()
        guard let encodedPubKey = base64PubKey.encodeURIComponent else {
            throw OWSAssertionError("Failed to url encode query params")
        }

        // We don't use URLComponents to generate this URL as it encodes '+' and '/'
        // in the base64 pub_key in a way the Android doesn't tolerate.
        let urlString = "\(kURLSchemeSGNLKey)://\(kURLHostLinkDevicePrefix)?uuid=\(deviceId)&pub_key=\(encodedPubKey)"
        guard let url = URL(string: urlString) else {
            throw OWSAssertionError("invalid url: \(urlString)")
        }

        return url
    }

    private func getDeviceId() -> Promise<String> {
        assert(provisioningSocket.state != .open)
        // TODO send Keep-Alive or ping frames at regular intervals
        // iOS uses ping frames elsewhere, but moxie seemed surprised we weren't
        // using the keepalive endpoint. Waiting to here back from him before proceeding.
        // (If it's sufficient, my preference would be to do like we do elsewhere and
        // use the ping frames)
        provisioningSocket.connect()
        return deviceIdPromise
    }
}

extension Deprecated_ProvisioningController: ProvisioningSocketDelegate {
    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveDeviceId deviceId: String) {
        owsAssertDebug(!deviceIdPromise.isSealed)
        deviceIdFuture.resolve(deviceId)
    }

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveEnvelope envelope: ProvisioningProtoProvisionEnvelope) {
        // After receiving the provisioning message, there's nothing else to retrieve from the provisioning socket
        provisioningSocket.disconnect()

        owsAssertDebug(!provisionEnvelopePromise.isSealed)
        return provisionEnvelopeFuture.resolve(envelope)
    }

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error) {
        deviceIdFuture.reject(error)
        provisionEnvelopeFuture.reject(error)
    }
}
