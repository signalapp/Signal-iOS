//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

private enum OpenableUrl {
    case phoneNumberLink(URL)
    case usernameLink(Usernames.UsernameLink)
    case stickerPack(StickerPackInfo)
    case groupInvite(URL)
    case signalProxy(URL)
    case linkDevice
    case completeIDEALDonation(Stripe.IDEALCallbackType)
    case callLink(CallLink)
    case quickRestore(URL)
}

class UrlOpener {
    private let appReadiness: AppReadinessSetter
    private let databaseStorage: SDSDatabaseStorage
    private let tsAccountManager: TSAccountManager

    init(
        appReadiness: AppReadinessSetter,
        databaseStorage: SDSDatabaseStorage,
        tsAccountManager: TSAccountManager,
    ) {
        self.appReadiness = appReadiness
        self.databaseStorage = databaseStorage
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Constants

    enum Constants {
        static let sgnlPrefix = "sgnl"
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
        if let linkDeviceURL = isSgnlLinkDeviceUrl(url) {
            switch linkDeviceURL.linkType {
            case .linkDevice: return .linkDevice
            case .quickRestore: return .quickRestore(url)
            }
        }
        if let donationType = Stripe.parseStripeIDEALCallback(url) {
            return .completeIDEALDonation(donationType)
        }
        if let callLink = CallLink(url: url) {
            return .callLink(callLink)
        }
        owsFailDebug("Couldn't parse URL")
        return nil
    }

    private static func parseSgnlAddStickersUrl(_ url: URL) -> StickerPackInfo? {
        guard
            let components = URLComponents(string: url.absoluteString),
            components.scheme == Constants.sgnlPrefix,
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

    /// Returns whether the given URL is an `sgnl://` link-new-device URL.
    private static func isSgnlLinkDeviceUrl(_ url: URL) -> DeviceProvisioningURL? {
        return DeviceProvisioningURL(urlString: url.absoluteString)
    }

    // MARK: - Opening URLs

    @MainActor
    func openUrl(_ parsedUrl: ParsedUrl, in window: UIWindow) {
        guard let rootViewController = window.rootViewController else {
            owsFailDebug("Ignoring URL; no root view controller.")
            return
        }
        if shouldDismiss(for: parsedUrl.openableUrl), rootViewController.presentedViewController != nil {
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
        case .groupInvite, .linkDevice, .phoneNumberLink, .signalProxy, .stickerPack, .usernameLink, .callLink, .quickRestore: return true
        }
    }

    @MainActor
    private func openUrlAfterDismissing(_ openableUrl: OpenableUrl, rootViewController: UIViewController) {
        do throws(NotRegisteredError) {
            try _openUrlAfterDismissing(openableUrl, rootViewController: rootViewController)
        } catch {
            Logger.warn("Ignoring url because we're not registered")
        }
    }

    @MainActor
    private func _openUrlAfterDismissing(_ openableUrl: OpenableUrl, rootViewController: UIViewController) throws(NotRegisteredError) {
        switch openableUrl {
        case .phoneNumberLink(let url):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            SignalDotMePhoneNumberLink.openChat(url: url, fromViewController: rootViewController)

        case .usernameLink(let link):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            Task {
                guard
                    let (_, aci) = await UsernameQuerier().queryForUsernameLink(
                        link: link,
                        fromViewController: rootViewController,
                    )
                else {
                    return
                }

                SignalApp.shared.presentConversationForAddress(
                    SignalServiceAddress(aci),
                    animated: true,
                )
            }

        case .stickerPack(let stickerPackInfo):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            let stickerPackViewController = StickerPackViewController(stickerPackInfo: stickerPackInfo)
            stickerPackViewController.present(from: rootViewController, animated: false)

        case .groupInvite(let url):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: rootViewController)

        case .signalProxy(let url):
            rootViewController.present(ProxyLinkSheetViewController(url: url)!, animated: true)

        case .linkDevice:
            let registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            guard registeredState.isPrimary else {
                Logger.warn("Ignoring URL; not primary device.")
                return
            }

            let linkDeviceWarningActionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "LINKED_DEVICE_URL_OPENED_ACTION_SHEET_EXTERNAL_URL_MESSAGE",
                    comment: "Message for an action sheet telling users how to link a device, when trying to open an external device-linking URL.",
                ),
            )

            let showLinkedDevicesAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "LINKED_DEVICES_TITLE",
                    comment: "Menu item and navbar title for the device manager",
                ),
            ) { _ in
                SignalApp.shared.showAppSettings(mode: .linkedDevices)
            }

            linkDeviceWarningActionSheet.addAction(showLinkedDevicesAction)
            linkDeviceWarningActionSheet.addAction(.cancel)
            rootViewController.presentActionSheet(linkDeviceWarningActionSheet)

        case .quickRestore:
            let registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            guard registeredState.isPrimary else {
                Logger.warn("Ignoring URL; not primary device.")
                return
            }

            let quickRestoreWarningActionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "QUICK_RESTORE_URL_OPENED_ACTION_SHEET_EXTERNAL_URL_MESSAGE",
                    comment: "Message for an action sheet telling users how to use quick restore, when trying to open an external quick restore URL.",
                ),
            )

            let showCameraViewAction = ActionSheetAction(
                title: CommonStrings.continueButton,
            ) { _ in
                SignalApp.shared.showCameraCaptureView { navController in
                    let sheet = HeroSheetViewController(
                        hero: .image(UIImage(named: "phone-qr")!),
                        title: OWSLocalizedString(
                            "QUICK_RESTORE_URL_OPENED_ACTION_SHEET_EXTERNAL_URL_ACTION_TITLE",
                            comment: "Title for sheet with info about scanning a Quick Restore QR code",
                        ),
                        body: OWSLocalizedString(
                            "QUICK_RESTORE_URL_OPENED_ACTION_SHEET_EXTERNAL_URL_ACTION_BODY",
                            comment: "Body for sheet with info about scanning a Quick Restore QR code",
                        ),
                        primaryButton: .dismissing(title: CommonStrings.okButton),
                    )
                    navController.topViewController?.present(sheet, animated: true)
                }
            }

            quickRestoreWarningActionSheet.addAction(showCameraViewAction)
            quickRestoreWarningActionSheet.addAction(.cancel)
            rootViewController.presentActionSheet(quickRestoreWarningActionSheet)

        case .completeIDEALDonation(let donationType):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            Task { [appReadiness, databaseStorage] in
                let handled = await DonationViewsUtil.attemptToContinueActiveIDEALDonation(
                    type: donationType,
                    databaseStorage: databaseStorage,
                )
                if handled {
                    Logger.info("[Donations] Completed iDEAL donation")
                    return
                }
                do {
                    try await DonationViewsUtil.restartAndCompleteInterruptedIDEALDonation(
                        type: donationType,
                        rootViewController: rootViewController,
                        databaseStorage: databaseStorage,
                        appReadiness: appReadiness,
                    )
                    Logger.info("[Donations] Completed iDEAL donation")
                } catch Signal.DonationJobError.timeout {
                    // This is an expected error case for pending donations
                } catch {
                    // Unexpected. Log a warning
                    Logger.warn("[Donations] Unexpected error encountered with iDEAL donation")
                }
            }

        case .callLink(let callLink):
            _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            GroupCallViewController.presentLobby(for: callLink)
        }
    }
}
