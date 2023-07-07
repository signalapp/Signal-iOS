//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalCoreKit
import SignalServiceKit
import SignalUI

protocol UsernameLinkScanDelegate: AnyObject {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink)
}

class UsernameLinkScanQRCodeViewController: OWSViewController, OWSNavigationChildController {
    private lazy var scanViewController = {
        let scanViewController = QRCodeScanViewController(
            appearance: .normal
        )

        scanViewController.delegate = self

        return scanViewController
    }()

    init(scanDelegate: UsernameLinkScanDelegate) {
        self.scanDelegate = scanDelegate

        super.init()
    }

    weak var scanDelegate: UsernameLinkScanDelegate?

    // MARK: - Views

    private lazy var instructionsLabel: UILabel = {
        let label = UILabel()

        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.text = OWSLocalizedString(
            "USERNAME_LINK_SCAN_QR_CODE_INSTRUCTIONS_LABEL",
            comment: "Text providing instructions on how to use the username link QR code scanning."
        )

        return label
    }()

    // MARK: - Lifecycle

    var navbarBackgroundColorOverride: UIColor? {
        return OWSTableViewController2.tableBackgroundColor(
            isUsingPresentedStyle: true
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(scanViewController)

        let instructionsWrapperView: UIView = {
            let wrapper = UIView()
            wrapper.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 20)

            wrapper.addSubview(instructionsLabel)
            instructionsLabel.autoPinEdgesToSuperviewMargins()

            return wrapper
        }()

        view.addSubview(scanViewController.view)
        view.addSubview(instructionsWrapperView)

        scanViewController.view.autoPinEdge(toSuperviewSafeArea: .top)
        scanViewController.view.autoPinEdge(toSuperviewSafeArea: .leading)
        scanViewController.view.autoPinEdge(toSuperviewSafeArea: .trailing)

        scanViewController.view.autoPinEdge(.bottom, to: .top, of: instructionsWrapperView)

        instructionsWrapperView.autoPinEdge(toSuperviewSafeArea: .leading)
        instructionsWrapperView.autoPinEdge(toSuperviewSafeArea: .trailing)
        instructionsWrapperView.autoPinEdge(toSuperviewSafeArea: .bottom)

        themeDidChange()
        contentSizeCategoryDidChange()
    }

    override func themeDidChange() {
        view.backgroundColor = navbarBackgroundColorOverride
        instructionsLabel.textColor = Theme.secondaryTextAndIconColor
    }

    override func contentSizeCategoryDidChange() {
        instructionsLabel.font = .dynamicTypeBody2
    }
}

extension UsernameLinkScanQRCodeViewController: QRCodeScanDelegate {
    func qrCodeScanViewScanned(
        _ qrCodeScanViewController: QRCodeScanViewController,
        qrCodeData: Data?,
        qrCodeString: String?
    ) -> QRCodeScanOutcome {
        guard let qrCodeString else {
            owsFailDebug("Unexpectedly missing QR code string!")
            return .continueScanning
        }

        guard
            let scannedUrl = URL(string: qrCodeString),
            let scannedUsernameLink = Usernames.UsernameLink(usernameLinkUrl: scannedUrl)
        else {
            owsFailDebug("Failed to create username link from scanned QR code!")
            return .continueScanning
        }

        guard let scanDelegate else {
            owsFailDebug("Missing scan delegate!")
            return .continueScanning
        }

        scanDelegate.usernameLinkScanned(scannedUsernameLink)
        return .stopScanning
    }

    func qrCodeScanViewDismiss(
        _ qrCodeScanViewController: QRCodeScanViewController
    ) {
        dismiss(animated: true)
    }
}
