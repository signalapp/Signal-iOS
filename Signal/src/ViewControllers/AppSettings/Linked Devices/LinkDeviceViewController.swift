//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol LinkDeviceViewControllerDelegate: AnyObject {
    typealias LinkNSyncData = (ephemeralBackupKey: MessageRootBackupKey, tokenId: DeviceProvisioningTokenId)
    @MainActor
    func didFinishLinking(_ linkNSyncData: LinkNSyncData?, from linkDeviceViewController: LinkDeviceViewController)
}

class LinkDeviceViewController: OWSViewController {

    weak var delegate: LinkDeviceViewControllerDelegate?
    private var context = ViewControllerContext.shared

    private var hasShownEducationSheet: Bool
    private weak var educationSheet: HeroSheetViewController?

    private lazy var qrCodeScanViewController = QRCodeScanViewController(appearance: .framed)

    init(skipEducationSheet: Bool) {
        self.hasShownEducationSheet = skipEducationSheet
        super.init()
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        title = CommonStrings.scanQRCodeTitle

#if TESTABLE_BUILD
        navigationItem.rightBarButtonItem = .init(
            title: LocalizationNotNeeded("ENTER"),
            style: .plain,
            target: self,
            action: #selector(manuallyEnterLinkURL),
        )
#endif

        qrCodeScanViewController.delegate = self

        addChild(qrCodeScanViewController)
        view.addSubview(qrCodeScanViewController.view)

        qrCodeScanViewController.view.autoPinEdgesToSuperviewEdges()
        qrCodeScanViewController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPad {
            UIDevice.current.ows_setOrientation(.portrait)
        }

        if !hasShownEducationSheet {
            let animationName = if traitCollection.userInterfaceStyle == .dark {
                "linking-device-dark"
            } else {
                "linking-device-light"
            }

            let sheet = HeroSheetViewController(
                hero: .animation(named: animationName, height: 192),
                title: OWSLocalizedString(
                    "LINK_DEVICE_SCANNING_INSTRUCTIONS_SHEET_TITLE",
                    comment: "Title for QR Scanning screen instructions sheet",
                ),
                body: OWSLocalizedString(
                    "LINK_DEVICE_SCANNING_INSTRUCTIONS_SHEET_BODY",
                    comment: "Title for QR Scanning screen instructions sheet",
                ),
                primaryButton: .dismissing(title: CommonStrings.okayButton),
            )

            DispatchQueue.main.async {
                self.present(sheet, animated: true)
                self.hasShownEducationSheet = true
                self.educationSheet = sheet
            }
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    private func dismissEducationSheetIfNecessary(completion: @escaping () -> Void) {
        if let educationSheet {
            educationSheet.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    private func safePresent(_ viewController: UIViewController) {
        dismissEducationSheetIfNecessary { [weak self] in
            self?.present(viewController, animated: true)
        }
    }

    // MARK: -

    private func confirmProvisioningWithUrl(_ deviceProvisioningUrl: DeviceProvisioningURL) {
        switch deviceProvisioningUrl.linkType {
        case .linkDevice:
            confirmProvisioning(with: deviceProvisioningUrl)
        case .quickRestore:
            // Ignore quick restore URLs in the link device controller
            break
        }
    }

    private func confirmProvisioning(with deviceProvisioningUrl: DeviceProvisioningURL) {
        if
            deviceProvisioningUrl.capabilities.contains(.linknsync)
        {
            let linkOrSyncSheet: LinkOrSyncPickerSheet = .load(
                didDismiss: {
                    self.popToLinkedDeviceList()
                },
                linkAndSync: {
                    self.provisionWithUrl(deviceProvisioningUrl, shouldLinkNSync: true)
                },
                linkOnly: {
                    self.provisionWithUrl(deviceProvisioningUrl, shouldLinkNSync: false)
                },
            )

            self.safePresent(linkOrSyncSheet)
        } else {
            let title = NSLocalizedString(
                "LINK_DEVICE_PERMISSION_ALERT_TITLE",
                comment: "confirm the users intent to link a new device",
            )
            let linkingDescription = NSLocalizedString(
                "LINK_DEVICE_PERMISSION_ALERT_BODY",
                comment: "confirm the users intent to link a new device",
            )

            let actionSheet = ActionSheetController(title: title, message: linkingDescription)
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { _ in
                    DispatchQueue.main.async {
                        self.popToLinkedDeviceList()
                    }
                },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: NSLocalizedString("CONFIRM_LINK_NEW_DEVICE_ACTION", comment: "Button text"),
                style: .default,
                handler: { _ in
                    self.provisionWithUrl(deviceProvisioningUrl, shouldLinkNSync: false)
                },
            ))
            safePresent(actionSheet)
        }
    }

    private func provisionWithUrl(
        _ deviceProvisioningUrl: DeviceProvisioningURL,
        shouldLinkNSync: Bool,
    ) {
        Task {
            do {
                let (ephemeralBackupKey, tokenId) = try await context.provisioningManager.provision(
                    with: deviceProvisioningUrl,
                    shouldLinkNSync: shouldLinkNSync,
                )
                Logger.info("Successfully provisioned device.")

                self.delegate?.didFinishLinking(
                    ephemeralBackupKey.map { ($0, tokenId) },
                    from: self,
                )
            } catch {
                Logger.error("Failed to provision device with error: \(error)")
                let actionSheet = self.retryActionSheetController(error: error, retryBlock: { [weak self] in
                    self?.provisionWithUrl(deviceProvisioningUrl, shouldLinkNSync: shouldLinkNSync)
                })
                self.safePresent(actionSheet)
            }
        }
    }

    private func retryActionSheetController(error: Error, retryBlock: @escaping () -> Void) -> ActionSheetController {
        switch error {
        case let error as DeviceLimitExceededError:
            let actionSheet = ActionSheetController(
                title: error.errorDescription,
                message: error.recoverySuggestion,
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.okButton,
                handler: { [weak self] _ in
                    self?.popToLinkedDeviceList()
                },
            ))
            return actionSheet

        default:
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString("LINKING_DEVICE_FAILED_TITLE", comment: "Alert Title"),
                message: error.userErrorDescription,
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default,
                handler: { action in retryBlock() },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { [weak self] action in
                    DispatchQueue.main.async { self?.dismiss(animated: true) }
                },
            ))
            return actionSheet
        }
    }

    func popToLinkedDeviceList(_ completion: (() -> Void)? = nil) {
        dismissEducationSheetIfNecessary { [weak navigationController] in
            navigationController?.popViewController(animated: true)
            // The method for adding a completion handler to popViewController in
            // UIViewController+SignalUI doesn't play well with UIHostingController
            navigationController?.transitionCoordinator?.animate(alongsideTransition: nil) { _ in
                UIViewController.attemptRotationToDeviceOrientation()
                completion?()
            }
        }
    }

#if TESTABLE_BUILD
    @objc
    private func manuallyEnterLinkURL() {
        let alertController = UIAlertController(
            title: LocalizationNotNeeded("Manually enter linking code."),
            message: LocalizationNotNeeded("Copy the URL represented by the QR code into the field below."),
            preferredStyle: .alert,
        )
        alertController.addTextField()
        alertController.addAction(UIAlertAction(
            title: CommonStrings.okayButton,
            style: .default,
            handler: { _ in
                guard let qrCodeString = alertController.textFields?.first?.text else { return }
                self.qrCodeScanViewScanned(
                    qrCodeData: nil,
                    qrCodeString: qrCodeString,
                )
            },
        ))
        alertController.addAction(UIAlertAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
        ))
        safePresent(alertController)
    }
#endif
}

extension LinkDeviceViewController: QRCodeScanDelegate {
    @discardableResult
    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?,
    ) -> QRCodeScanOutcome {
        AssertIsOnMainThread()

        guard let qrCodeString else {
            // Only accept QR codes with a valid string payload.
            return .continueScanning
        }

        guard let url = DeviceProvisioningURL(urlString: qrCodeString) else {
            Logger.error("Unable to parse provisioning params from QRCode: \(qrCodeString)")

            let title = NSLocalizedString("LINK_DEVICE_INVALID_CODE_TITLE", comment: "report an invalid linking code")
            let body = NSLocalizedString("LINK_DEVICE_INVALID_CODE_BODY", comment: "report an invalid linking code")

            let actionSheet = ActionSheetController(title: title, message: body)
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { _ in
                    DispatchQueue.main.async {
                        self.popToLinkedDeviceList()
                    }
                },
            ))
            actionSheet.addAction(ActionSheetAction(
                title: NSLocalizedString("LINK_DEVICE_RESTART", comment: "attempt another linking"),
                style: .default,
                handler: { _ in
                    self.qrCodeScanViewController.tryToStartScanning()
                },
            ))
            safePresent(actionSheet)

            return .stopScanning
        }

        confirmProvisioningWithUrl(url)

        return .stopScanning
    }

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: SignalUI.QRCodeScanViewController) {
        AssertIsOnMainThread()
        popToLinkedDeviceList()
    }
}
