//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import UIKit

final class FingerprintScanViewController: OWSViewController, OWSNavigationChildController {

    private let recipientAci: Aci
    private let recipientIdentity: OWSRecipientIdentity
    private let contactName: String
    private let identityKey: Data
    private let fingerprint: OWSFingerprint

    private lazy var qrCodeScanViewController = QRCodeScanViewController(appearance: .framed)

    init(
        recipientAci: Aci,
        recipientIdentity: OWSRecipientIdentity,
        fingerprint: OWSFingerprint
    ) {
        self.recipientAci = recipientAci
        self.recipientIdentity = recipientIdentity
        self.identityKey = recipientIdentity.identityKey

        self.fingerprint = fingerprint
        self.contactName = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(recipientAci), tx: tx).resolvedValue()
        }

        super.init()

        title = CommonStrings.scanQRCodeTitle
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return .ows_gray10
    }

    public var navbarTintColorOverride: UIColor? {
        return Theme.lightThemePrimaryColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        qrCodeScanViewController.delegate = self
        view.addSubview(qrCodeScanViewController.view)
        qrCodeScanViewController.view.autoPinWidthToSuperview()
        qrCodeScanViewController.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        addChild(qrCodeScanViewController)

        let footerView = UIView()
        footerView.backgroundColor = .ows_gray10
        view.addSubview(footerView)
        footerView.autoPinWidthToSuperview()
        footerView.autoPinEdge(.top, to: .bottom, of: qrCodeScanViewController.view)
        footerView.autoPinEdge(toSuperviewEdge: .bottom)

        let cameraInstructionLabel = UILabel()
        cameraInstructionLabel.text = NSLocalizedString(
            "SCAN_CODE_INSTRUCTIONS",
            comment: "label presented once scanning (camera) view is visible."
        )
        cameraInstructionLabel.font = .systemFont(ofSize: .scaleFromIPhone5To7Plus(14, 18))
        cameraInstructionLabel.textColor = .ows_gray60
        cameraInstructionLabel.textAlignment = .center
        cameraInstructionLabel.numberOfLines = 0
        cameraInstructionLabel.lineBreakMode = .byWordWrapping
        footerView.addSubview(cameraInstructionLabel)
        cameraInstructionLabel.autoPinWidthToSuperview(withMargin: .scaleFromIPhone5To7Plus(16, 30))
        let instructionsVMargin = CGFloat.scaleFromIPhone5To7Plus(10, 20)
        cameraInstructionLabel.autoPin(toBottomLayoutGuideOf: self, withInset: instructionsVMargin)
        cameraInstructionLabel.autoPinEdge(toSuperviewEdge: .top, withInset: instructionsVMargin)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        qrCodeScanViewController.view.isHidden = true
        super.dismiss(animated: flag, completion: completion)
    }

    // MARK: -

    private func verifyCombinedFingerprintData(_ combinedFingerprintData: Data) {
        AssertIsOnMainThread()

        func showSuccess() {
            FingerprintScanViewController.showVerificationSucceeded(
                from: self,
                identityKey: identityKey,
                recipientAci: recipientAci,
                contactName: contactName,
                tag: "[\(type(of: self))]"
            )
        }

        func showFailure(localizedErrorDescription: String) {
            FingerprintScanViewController.showVerificationFailed(
                from: self,
                isUserError: false,
                localizedErrorDescription: localizedErrorDescription,
                retry: { self.qrCodeScanViewController.tryToStartScanning() },
                cancel: { self.navigationController?.popViewController(animated: true) },
                tag: "[\(type(of: self))]"
            )
        }

        switch fingerprint.matchesLogicalFingerprintsData(combinedFingerprintData) {
        case .match:
            showSuccess()
        case .noMatch(let localizedErrorDescription), .weHaveOldVersion(let localizedErrorDescription), .theyHaveOldVersion(let localizedErrorDescription):
            // We reached the end, show the error for the last one.
            showFailure(localizedErrorDescription: localizedErrorDescription)
        }
    }

    static func showVerificationSucceeded(
        from viewController: UIViewController,
        identityKey: Data,
        recipientAci: Aci,
        contactName: String,
        tag: String
    ) {
        AssertIsOnMainThread()

        Logger.info("\(tag) Successfully verified safety numbers.")

        let successTitle = NSLocalizedString("SUCCESSFUL_VERIFICATION_TITLE", comment: "")
        let descriptionFormat = NSLocalizedString(
            "SUCCESSFUL_VERIFICATION_DESCRIPTION",
            comment: "Alert body after verifying privacy with {{other user's name}}"
        )
        let successDescription = String(format: descriptionFormat, contactName)
        let actionSheet = ActionSheetController(title: successTitle, message: successDescription)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString(
                "FINGERPRINT_SCAN_VERIFY_BUTTON",
                comment: "Button that marks user as verified after a successful fingerprint scan."
            ),
            style: .default,
            handler: { _ in
                DependenciesBridge.shared.db.write { tx in
                    let identityManager = DependenciesBridge.shared.identityManager
                    identityManager.saveIdentityKey(identityKey, for: recipientAci, tx: tx)
                    _ = identityManager.setVerificationState(
                        .verified,
                        of: identityKey,
                        for: SignalServiceAddress(recipientAci),
                        isUserInitiatedChange: true,
                        tx: tx
                    )
                }
                if let navigationController = viewController.navigationController {
                    navigationController.popViewController(animated: true)
                } else {
                    viewController.dismiss(animated: true)
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.dismissButton,
            style: .cancel,
            handler: { _ in
                if let navigationController = viewController.navigationController {
                    navigationController.popViewController(animated: true)
                } else {
                    viewController.dismiss(animated: true)
                }
            }
        ))

        viewController.presentActionSheet(actionSheet)
    }

    static func showVerificationFailed(
        from viewController: UIViewController,
        isUserError: Bool,
        localizedErrorDescription: String,
        retry: (() -> Void)? = nil,
        cancel: (() -> Void)? = nil,
        tag: String
    ) {
        Logger.info("\(tag) Failed to verify safety numbers.")

        // We don't want to show a big scary "VERIFICATION FAILED" when it's just user error.
        let actionSheet = ActionSheetController(
            title: isUserError ? nil : NSLocalizedString("FAILED_VERIFICATION_TITLE", comment: "alert title"),
            message: localizedErrorDescription
        )

        if let retry {
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default,
                handler: { _ in
                    retry()
                }
            ))
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)

        viewController.presentActionSheet(actionSheet)

        Logger.warn("\(tag) Identity verification failed")
    }
}

extension FingerprintScanViewController: QRCodeScanDelegate {
    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?
    ) -> QRCodeScanOutcome {

        guard let qrCodeData else {
            // Only accept QR codes with a valid data (not string) payload.
            return .continueScanning
        }

        verifyCombinedFingerprintData(qrCodeData)

        // Stop scanning even if verification failed.
        return .stopScanning
    }

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController) {
        AssertIsOnMainThread()

        navigationController?.popViewController(animated: true)
    }
}
