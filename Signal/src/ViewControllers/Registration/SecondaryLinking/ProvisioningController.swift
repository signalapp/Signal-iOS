//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public class ProvisioningController {

    // MARK: - Dependencies

    var accountManager: AccountManager {
        return AppEnvironment.shared.accountManager
    }

    // MARK: -

    let onboardingController: OnboardingController
    let provisioningCipher: ProvisioningCipher

    let provisioningSocket: ProvisioningSocket

    var deviceIdPromise: Promise<String>
    var deviceIdResolver: Resolver<String>

    var provisionEnvelopePromise: Promise<ProvisioningProtoProvisionEnvelope>
    var provisionEnvelopeResolver: Resolver<ProvisioningProtoProvisionEnvelope>

    public init(onboardingController: OnboardingController) {
        self.onboardingController = onboardingController
        provisioningCipher = ProvisioningCipher.generate()

        (self.deviceIdPromise, self.deviceIdResolver) = Promise.pending()
        (self.provisionEnvelopePromise, self.provisionEnvelopeResolver) = Promise.pending()

        provisioningSocket = ProvisioningSocket()

        provisioningSocket.delegate = self
    }

    public func resetPromises() {
        (self.deviceIdPromise, self.deviceIdResolver) = Promise.pending()
        (self.provisionEnvelopePromise, self.provisionEnvelopeResolver) = Promise.pending()
    }

    // MARK: -

    func didConfirmSecondaryDevice(from viewController: SecondaryLinkingPrepViewController) {
        guard let navigationController = viewController.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        let qrCodeViewController = SecondaryLinkingQRCodeViewController(provisioningController: self)
        navigationController.pushViewController(qrCodeViewController, animated: true)

        awaitProvisionMessage.done { [weak self, weak navigationController] _ in
            guard let self = self else { throw PMKError.cancelled }
            guard let navigationController = navigationController else { throw PMKError.cancelled }

            let confirmVC = SecondaryLinkingSetDeviceNameViewController(provisioningController: self)
            navigationController.pushViewController(confirmVC, animated: true)
        }.catch { error in
            switch error {
            case PMKError.cancelled:
                Logger.info("cancelled")
            default:
                Logger.warn("error: \(error)")
                let alert = UIAlertController(title: NSLocalizedString("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN", comment: "alert title"),
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonStrings.retryButton,
                                              accessibilityIdentifier: "alert.retry",
                                              style: .default,
                                              handler: { _ in
                                                self.resetPromises()
                                                navigationController.popViewController(animated: true)
                }))
                navigationController.presentAlert(alert)
            }
        }.retainUntilComplete()
    }

    func didSetDeviceName(_ deviceName: String, from viewController: UIViewController) {
        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            self.completeLinking(deviceName: deviceName).done {
                modal.dismiss {
                    self.onboardingController.linkingDidComplete(from: viewController)
                }
            }.catch { error in
                Logger.warn("error: \(error)")
                let alert = UIAlertController(title: NSLocalizedString("SECONDARY_LINKING_ERROR_WAITING_FOR_SCAN", comment: "alert title"),
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonStrings.retryButton,
                                              accessibilityIdentifier: "alert.retry",
                                              style: .default,
                                              handler: { _ in
                                                self.didSetDeviceName(deviceName, from: viewController)
                }))
                modal.dismiss {
                    viewController.presentAlert(alert)
                }
            }.retainUntilComplete()
        }

        ModalActivityIndicatorViewController.present(fromViewController: viewController,
                                                     canCancel: false,
                                                     backgroundBlock: backgroundBlock)
    }

    public func getProvisioningURL() -> Promise<URL> {
        return getDeviceId().map { [weak self] deviceId in
            guard let self = self else { throw PMKError.cancelled }

            return try self.buildProvisioningUrl(deviceId: deviceId)
        }
    }

    public lazy var awaitProvisionMessage: Promise<ProvisionMessage> = {
        return provisionEnvelopePromise.map { [weak self] envelope in
            guard let self = self else { throw PMKError.cancelled }
            return try self.provisioningCipher.decrypt(envelope: envelope)
        }
    }()

    public func completeLinking(deviceName: String) -> Promise<Void> {
        return awaitProvisionMessage.then { [weak self] provisionMessage -> Promise<Void> in
            guard let self = self else { throw PMKError.cancelled }

            return self.accountManager.completeSecondaryLinking(provisionMessage: provisionMessage,
                                                                deviceName: deviceName)
        }
    }

    // MARK: -

    private func buildProvisioningUrl(deviceId: String) throws -> URL {
        let base64PubKey: String = provisioningCipher.secondaryDevicePublicKey.serialized.base64EncodedString()

        var urlComponents = URLComponents()
        urlComponents.scheme = "tsdevice"
        urlComponents.queryItems = [
            URLQueryItem(name: "uuid", value: deviceId),
            URLQueryItem(name: "pub_key", value: base64PubKey)
        ]

        guard let url = urlComponents.url else {
            throw OWSAssertionError("invalid urlComponents: \(urlComponents)")
        }

        return url
    }

    private func getDeviceId() -> Promise<String> {
        assert(provisioningSocket.state == .connecting)
        // TODO send Keep-Alive or ping frames at regular intervals
        // iOS uses ping frames elsewhere, but moxie seemed surprised we weren't
        // using the keepalive endpoint. Waiting to here back from him before proceeding.
        // (If it's sufficient, my preference would be to do like we do elsewhere and
        // use the ping frames)
        provisioningSocket.connect()
        return deviceIdPromise
    }
}

extension ProvisioningController: ProvisioningSocketDelegate {
    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveDeviceId deviceId: String) {
        assert(deviceIdPromise.isPending)
        deviceIdResolver.fulfill(deviceId)
    }

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveEnvelope envelope: ProvisioningProtoProvisionEnvelope) {
        // After receiving the provisioning message, there's nothing else to retreive from the provisioning socket
        provisioningSocket.disconnect()

        assert(provisionEnvelopePromise.isPending)
        return provisionEnvelopeResolver.fulfill(envelope)
    }

    public func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error) {
        deviceIdResolver.reject(error)
        provisionEnvelopeResolver.reject(error)
    }
}
