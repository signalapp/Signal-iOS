//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import UIKit

class FingerprintScanViewController: OWSViewController {

    private let recipientAddress: SignalServiceAddress
    private let recipientIdentity: OWSRecipientIdentity
    private let contactName: String
    private let identityKey: IdentityKey
    private let fingerprint: OWSFingerprint

    private lazy var qrCodeScanViewController = QRCodeScanViewController(appearance: .normal)

    init?(recipientAddress: SignalServiceAddress, recipientIdentity: OWSRecipientIdentity) {
        owsAssertDebug(recipientAddress.isValid)

        self.recipientAddress = recipientAddress
        self.recipientIdentity = recipientIdentity
        self.identityKey = recipientIdentity.identityKey
        guard let fingerprint = OWSFingerprintBuilder(
            accountManager: TSAccountManager.shared,
            contactsManager: SSKEnvironment.shared.contactsManagerRef
        ).fingerprint(theirSignalAddress: recipientAddress, theirIdentityKey: recipientIdentity.identityKey) else {
            return nil
        }
        self.fingerprint = fingerprint
        self.contactName = SSKEnvironment.shared.contactsManagerRef.displayName(for: recipientAddress)

        super.init()

        title = NSLocalizedString("SCAN_QR_CODE_VIEW_TITLE", comment: "Title for the 'scan QR code' view.")
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
        footerView.backgroundColor = .ows_gray75
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
        cameraInstructionLabel.textColor = .white
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

        switch fingerprint.matchesLogicalFingerprintsData(combinedFingerprintData) {
        case .match:
            FingerprintScanViewController.showVerificationSucceeded(
                from: self,
                identityKey: identityKey,
                recipientAddress: recipientAddress,
                contactName: contactName,
                tag: logTag
            )
        case .noMatch(let localizedErrorDescription):
            FingerprintScanViewController.showVerificationFailed(
                from: self,
                isUserError: false,
                localizedErrorDescription: localizedErrorDescription,
                retry: { self.qrCodeScanViewController.tryToStartScanning() },
                cancel: { self.navigationController?.popViewController(animated: true) },
                tag: logTag
            )
        }
    }

    static func showVerificationSucceeded(
        from viewController: UIViewController,
        identityKey: Data,
        recipientAddress: SignalServiceAddress,
        contactName: String,
        tag: String
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(recipientAddress.isValid)

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
                OWSIdentityManager.shared.setVerificationState(
                    .verified,
                    identityKey: identityKey,
                    address: recipientAddress,
                    isUserInitiatedChange: true
                )
                viewController.dismiss(animated: true)
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.dismissButton,
            style: .cancel,
            handler: { _ in
                viewController.dismiss(animated: true)
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
        _ qrCodeScanViewController: QRCodeScanViewController,
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
