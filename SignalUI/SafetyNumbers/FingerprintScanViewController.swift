//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import UIKit

class FingerprintScanViewController: OWSViewController, OWSNavigationChildController {

    private let recipientAci: Aci
    private let contactName: String
    private let fingerprint: OWSFingerprint

    private lazy var qrCodeScanViewController = QRCodeScanViewController(appearance: .framed)

    init(
        recipientAci: Aci,
        recipientName: String,
        fingerprint: OWSFingerprint,
    ) {
        self.recipientAci = recipientAci

        self.fingerprint = fingerprint
        self.contactName = recipientName

        super.init()

        title = CommonStrings.scanQRCodeTitle
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        qrCodeScanViewController.delegate = self
        view.addSubview(qrCodeScanViewController.view)
        qrCodeScanViewController.view.autoPinWidthToSuperview()
        qrCodeScanViewController.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        addChild(qrCodeScanViewController)

        let footerView = UIView()
        footerView.backgroundColor = .Signal.secondaryBackground
        view.addSubview(footerView)
        footerView.autoPinWidthToSuperview()
        footerView.autoPinEdge(.top, to: .bottom, of: qrCodeScanViewController.view)
        footerView.autoPinEdge(toSuperviewEdge: .bottom)

        let cameraInstructionLabel = UILabel()
        cameraInstructionLabel.text = NSLocalizedString(
            "SCAN_CODE_INSTRUCTIONS",
            comment: "label presented once scanning (camera) view is visible.",
        )
        cameraInstructionLabel.font = .systemFont(ofSize: .scaleFromIPhone5To7Plus(14, 18))
        cameraInstructionLabel.textColor = .Signal.secondaryLabel
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
                identityKey: fingerprint.theirAciIdentityKey,
                recipientAci: recipientAci,
                contactName: contactName,
                tag: "[\(type(of: self))]",
            )
        }

        func showFailure(localizedErrorDescription: String) {
            FingerprintScanViewController.showVerificationFailed(
                from: self,
                isUserError: false,
                localizedErrorDescription: localizedErrorDescription,
                retry: { self.qrCodeScanViewController.tryToStartScanning() },
                cancel: { self.navigationController?.popViewController(animated: true) },
                tag: "[\(type(of: self))]",
            )
        }

        let combinedFingerprints: Textsecure_CombinedFingerprints
        do {
            combinedFingerprints = try Textsecure_CombinedFingerprints(serializedBytes: combinedFingerprintData)
        } catch {
            Logger.warn("fingerprint failure: \(error)")
            showFailure(localizedErrorDescription: OWSLocalizedString("PRIVACY_VERIFICATION_FAILURE_INVALID_QRCODE", comment: "alert body"))
            return
        }
        do throws(OWSFingerprint.MatchError) {
            try fingerprint.checkAgainst(combinedFingerprints: combinedFingerprints)
            showSuccess()
        } catch {
            Logger.warn("verification failure: \(error)")
            let message: String
            switch error {
            case .theyHaveOldVersion:
                message = OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_WITH_OLD_REMOTE_VERSION", comment: "alert body")
            case .weHaveOldVersion:
                message = OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_WITH_OLD_LOCAL_VERSION", comment: "alert body")
            case .theyHaveWrongKeyForUs:
                let descriptionFormat = OWSLocalizedString(
                    "PRIVACY_VERIFICATION_FAILED_THEY_HAVE_WRONG_KEY_FOR_ME",
                    comment: "Alert body when verifying with {{contact name}}",
                )
                message = String.nonPluralLocalizedStringWithFormat(descriptionFormat, self.contactName)
            case .weHaveWrongKeyForThem:
                let descriptionFormat = OWSLocalizedString(
                    "PRIVACY_VERIFICATION_FAILED_I_HAVE_WRONG_KEY_FOR_THEM",
                    comment: "Alert body when verifying with {{contact name}}",
                )
                message = String.nonPluralLocalizedStringWithFormat(descriptionFormat, self.contactName)
            }
            showFailure(localizedErrorDescription: message)
        }
    }

    static func showVerificationSucceeded(
        from viewController: UIViewController,
        identityKey: IdentityKey,
        recipientAci: Aci,
        contactName: String,
        tag: String,
    ) {
        AssertIsOnMainThread()

        Logger.info("\(tag) Successfully verified safety numbers.")

        let successTitle = NSLocalizedString("SUCCESSFUL_VERIFICATION_TITLE", comment: "")
        let descriptionFormat = NSLocalizedString(
            "SUCCESSFUL_VERIFICATION_DESCRIPTION",
            comment: "Alert body after verifying privacy with {{other user's name}}",
        )
        let successDescription = String.nonPluralLocalizedStringWithFormat(descriptionFormat, contactName)
        let actionSheet = ActionSheetController(title: successTitle, message: successDescription)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString(
                "FINGERPRINT_SCAN_VERIFY_BUTTON",
                comment: "Button that marks user as verified after a successful fingerprint scan.",
            ),
            style: .default,
            handler: { _ in
                DependenciesBridge.shared.db.write { tx in
                    let identityManager = DependenciesBridge.shared.identityManager
                    identityManager.saveIdentityKey(identityKey, for: recipientAci, tx: tx)
                    _ = identityManager.setVerificationState(
                        .verified,
                        of: identityKey.publicKey.keyBytes,
                        for: SignalServiceAddress(recipientAci),
                        isUserInitiatedChange: true,
                        tx: tx,
                    )
                }
                if let navigationController = viewController.navigationController {
                    navigationController.popViewController(animated: true)
                } else {
                    viewController.dismiss(animated: true)
                }
            },
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
            },
        ))

        viewController.presentActionSheet(actionSheet)
    }

    static func showVerificationFailed(
        from viewController: UIViewController,
        isUserError: Bool,
        localizedErrorDescription: String,
        retry: (() -> Void)? = nil,
        cancel: (() -> Void)? = nil,
        tag: String,
    ) {
        Logger.info("\(tag) Failed to verify safety numbers.")

        // We don't want to show a big scary "VERIFICATION FAILED" when it's just user error.
        let actionSheet = ActionSheetController(
            title: isUserError ? nil : NSLocalizedString("FAILED_VERIFICATION_TITLE", comment: "alert title"),
            message: localizedErrorDescription,
        )

        if let retry {
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default,
                handler: { _ in
                    retry()
                },
            ))
        }

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                cancel?()
            },
        ))

        viewController.presentActionSheet(actionSheet)

        Logger.warn("\(tag) Identity verification failed")
    }
}

extension FingerprintScanViewController: QRCodeScanDelegate {
    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?,
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
