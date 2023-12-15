//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import SignalMessaging

private enum OpenableUrl {
    case phoneNumberLink(URL)
    case usernameLink(Usernames.UsernameLink)
    case stickerPack(StickerPackInfo)
    case groupInvite(URL)
    case signalProxy(URL)
    case linkDevice(DeviceProvisioningURL)
    case completeIDEALDonation(Stripe.IDEALCallbackType)
}

class UrlOpener {
    private let databaseStorage: SDSDatabaseStorage
    private let tsAccountManager: TSAccountManager

    init(
        databaseStorage: SDSDatabaseStorage,
        tsAccountManager: TSAccountManager
    ) {
        self.databaseStorage = databaseStorage
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Parsing URLs

    struct ParsedUrl {
        fileprivate let openableUrl: OpenableUrl
    }

    static func parseUrl(_ url: URL) -> ParsedUrl? {
        guard let openableUrl = parseOpenableUrl(url) else {
            return nil
        }
        return ParsedUrl(openableUrl: openableUrl)
    }

    private static func parseOpenableUrl(_ url: URL) -> OpenableUrl? {
        if SignalDotMePhoneNumberLink.isPossibleUrl(url) {
            return .phoneNumberLink(url)
        }
        if let usernameLink = Usernames.UsernameLink(usernameLinkUrl: url) {
            return .usernameLink(usernameLink)
        }
        if StickerPackInfo.isStickerPackShare(url), let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) {
            return .stickerPack(stickerPackInfo)
        }
        if let stickerPackInfo = parseSgnlAddStickersUrl(url) {
            return .stickerPack(stickerPackInfo)
        }
        if GroupManager.isPossibleGroupInviteLink(url) {
            return .groupInvite(url)
        }
        if SignalProxy.isValidProxyLink(url) {
            return .signalProxy(url)
        }
        if let deviceProvisiongUrl = parseSgnlLinkDeviceUrl(url) {
            return .linkDevice(deviceProvisiongUrl)
        }
        if let donationType = Stripe.parseStripeIDEALCallback(url) {
            return .completeIDEALDonation(donationType)
        }
        owsFailDebug("Couldn't parse URL")
        return nil
    }

    private static func parseSgnlAddStickersUrl(_ url: URL) -> StickerPackInfo? {
        guard
            let components = URLComponents(string: url.absoluteString),
            components.scheme == kURLSchemeSGNLKey,
            components.host?.hasPrefix("addstickers") == true,
            let queryItems = components.queryItems
        else {
            return nil
        }
        var packIdHex: String?
        var packKeyHex: String?
        for queryItem in queryItems {
            switch queryItem.name {
            case "pack_id":
                owsAssertDebug(packIdHex == nil)
                packIdHex = queryItem.value
            case "pack_key":
                owsAssertDebug(packKeyHex == nil)
                packKeyHex = queryItem.value
            default:
                Logger.warn("Unknown query item in sticker pack url")
            }
        }
        return StickerPackInfo.parse(packIdHex: packIdHex, packKeyHex: packKeyHex)
    }

    private static func parseSgnlLinkDeviceUrl(_ url: URL) -> DeviceProvisioningURL? {
        guard url.scheme == kURLSchemeSGNLKey, url.host?.hasPrefix(kURLHostLinkDevicePrefix) == true else {
            return nil
        }
        return DeviceProvisioningURL(urlString: url.absoluteString)
    }

    // MARK: - Opening URLs

    func openUrl(_ parsedUrl: ParsedUrl, in window: UIWindow) {
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return owsFailDebug("Ignoring URL; not registered.")
        }
        guard let rootViewController = window.rootViewController else {
            return owsFailDebug("Ignoring URL; no root view controller.")
        }
        if shouldDismiss(for: parsedUrl.openableUrl) && rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: false, completion: {
                self.openUrlAfterDismissing(parsedUrl.openableUrl, rootViewController: rootViewController)
            })
        } else {
            openUrlAfterDismissing(parsedUrl.openableUrl, rootViewController: rootViewController)
        }
    }

    private func shouldDismiss(for url: OpenableUrl) -> Bool {
        switch url {
        case .completeIDEALDonation: return false
        case .groupInvite, .linkDevice, .phoneNumberLink, .signalProxy, .stickerPack, .usernameLink: return true
        }
    }

    private func openUrlAfterDismissing(_ openableUrl: OpenableUrl, rootViewController: UIViewController) {
        switch openableUrl {
        case .phoneNumberLink(let url):
            SignalDotMePhoneNumberLink.openChat(url: url, fromViewController: rootViewController)

        case .usernameLink(let link):
            databaseStorage.read { tx in
                UsernameQuerier().queryForUsernameLink(
                    link: link,
                    fromViewController: rootViewController,
                    tx: tx
                ) { aci in
                    SignalApp.shared.presentConversationForAddress(
                        SignalServiceAddress(aci),
                        animated: true
                    )
                }
            }

        case .stickerPack(let stickerPackInfo):
            let stickerPackViewController = StickerPackViewController(stickerPackInfo: stickerPackInfo)
            stickerPackViewController.present(from: rootViewController, animated: false)

        case .groupInvite(let url):
            GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: rootViewController)

        case .signalProxy(let url):
            rootViewController.present(ProxyLinkSheetViewController(url: url)!, animated: true)

        case .linkDevice(let deviceProvisioningURL):
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
                return owsFailDebug("Ignoring URL; not primary device.")
            }
            let linkedDevicesViewController = LinkedDevicesTableViewController()
            let linkDeviceViewController = LinkDeviceViewController()
            linkDeviceViewController.delegate = linkedDevicesViewController

            let navigationController = AppSettingsViewController.inModalNavigationController()
            var viewControllers = navigationController.viewControllers
            viewControllers.append(linkedDevicesViewController)
            viewControllers.append(linkDeviceViewController)
            navigationController.setViewControllers(viewControllers, animated: false)

            rootViewController.presentFormSheet(navigationController, animated: false) {
                linkDeviceViewController.confirmProvisioningWithUrl(deviceProvisioningURL)
            }

        case .completeIDEALDonation(let donationType):
            self.attemptToContinueActiveIDEALDonation(type: donationType)
                .then(on: DispatchQueue.main) { [weak self] handled -> Promise<Void> in
                    guard let self else { return .value(()) }
                    if handled {
                        return Promise.value(())
                    }
                    return self.restartAndCompleteInterruptedIDEALDonation(
                        type: donationType,
                        rootViewController: rootViewController
                    )
                }.cauterize()
        }
    }
}

// MARK: iDEAL donation completion

private extension UrlOpener {

    /// If the donation can't be continued, build back up the donation UI and attempt to complete the donation.
    private func restartAndCompleteInterruptedIDEALDonation(
        type donationType: Stripe.IDEALCallbackType,
        rootViewController: UIViewController
    ) -> Promise<Void> {
        let success = {
            switch donationType {
            case .oneTime(didSucceed: let success, _), .monthly(didSucceed: let success, _, _):
                return success
            }
        }()

        let (promise, future) = Promise<Void>.pending()

        let completion = {
            guard let frontVc = CurrentAppContext().frontmostViewController() else {
                future.resolve(())
                return
            }

            // Build up the Donation UI
            let appSettings = AppSettingsViewController.inModalNavigationController()
            let donationsVC = DonationSettingsViewController()
            appSettings.viewControllers += [ donationsVC ]

            frontVc.presentFormSheet(appSettings, animated: false) {
                AssertIsOnMainThread()
                guard success else {
                    future.reject(OWSUnretryableError())
                    return
                }

                DonationViewsUtil.wrapPromiseInProgressView(
                    from: donationsVC,
                    promise: DonationViewsUtil.completeIDEALDonation(
                        donationType: donationType,
                        databaseStorage: self.databaseStorage
                    ) { error, badge, paymentMethod in
                        guard let badge else { return }
                        if let error {
                            DonationViewsUtil.presentErrorSheet(
                                from: donationsVC,
                                error: error,
                                mode: donationType.asDonationMode,
                                badge: badge,
                                paymentMethod: paymentMethod
                            )
                        } else {
                            guard
                                let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.loadWithSneakyTransaction(
                                    successMode: donationType.asSuccessMode
                                )
                            else { return }

                            badgeThanksSheetPresenter.presentBadgeThanksAndClearSuccess(
                                fromViewController: donationsVC
                            )
                        }
                    }
                ).done {
                    future.resolve(())
                }.catch { error in
                    future.reject(error)
                }
            }
        }

        if rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: false) {
                completion()
            }
        } else {
            completion()
        }
        return promise
    }

    /// Attempts to seamlessly continue the donation, if the app state is still at the appropriate step in the iDEAL donation flow.
    ///
    /// - Returns:
    /// `true` if the donation was continued by previously-constructed UI.
    /// `false` otherwise,  in which case the caller is responsible for "reconstructing" the appropriate step in the
    /// donation flow and continuing the donation.
    private func attemptToContinueActiveIDEALDonation(
        type donationType: Stripe.IDEALCallbackType
    ) -> Promise<Bool> {
        // Inspect this view controller to find out if the layout is as expected.
        guard
            let frontVC = CurrentAppContext().frontmostViewController(),
            let navController = frontVC.presentingViewController as? UINavigationController,
            let vc = navController.viewControllers.last,
            let donationPaymentVC = vc as? DonationPaymentDetailsViewController,
            donationPaymentVC.threeDSecureAuthenticationSession != nil
        else {
            // Not in the expected donation flow, so revert to building
            // the donation view stack from scratch
            return .value(false)
        }

        let (promise, future) = Promise<Bool>.pending()

        frontVC.dismiss(animated: true) {
            let (success, intentId) = {
                switch donationType {
                case
                    let .oneTime(success, intent),
                    let .monthly(success, _, intent):
                    return (success, intent)
                }
            }()

            // Attempt to slide back into the current donation flow by completing
            // the active 3DS session with the intent.  If the payment was externally
            // failed, pass that into the existing donation flow to be handled inline
            let continuedWithActiveDonation = donationPaymentVC.completeExternal3DS(
                success: success,
                intentID: intentId
            )

            future.resolve(continuedWithActiveDonation)
        }
        return promise
    }
}

private extension Stripe.IDEALCallbackType {

    var asSuccessMode: ReceiptCredentialResultStore.Mode {
        switch self {
        case .oneTime: return .oneTimeBoost
        case .monthly: return .recurringSubscriptionInitiation
        }
    }

    var asDonationMode: DonateViewController.DonateMode {
        switch self {
        case .oneTime: return .oneTime
        case .monthly: return .monthly
        }
    }
}
