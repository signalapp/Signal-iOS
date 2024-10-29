//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PureLayout
import SignalServiceKit
import SignalUI

protocol UsernameLinkScanDelegate: AnyObject {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink)
}

class UsernameLinkScanQRCodeViewController: OWSViewController, OWSNavigationChildController {
    var preferredNavigationBarStyle: OWSNavigationBarStyle { .blur }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    var selectedAttachment: ImagePickerAttachment?

    weak var scanDelegate: UsernameLinkScanDelegate?

    init(scanDelegate: UsernameLinkScanDelegate) {
        self.scanDelegate = scanDelegate

        super.init()
    }

    private var context: ViewControllerContext { .shared }

    // MARK: - Views

    private lazy var scanViewController = {
        let scanViewController = QRCodeScanViewController(
            appearance: .framed,
            showUploadPhotoButton: true
        )

        scanViewController.delegate = self

        return scanViewController
    }()

    private lazy var instructionsLabel: UILabel = {
        let label = UILabel()

        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.text = OWSLocalizedString(
            "USERNAME_LINK_SCAN_QR_CODE_INSTRUCTIONS_LABEL",
            comment: "Text providing instructions on how to use the username link QR code scanning."
        )

        // Always use dark theme since it sits over the scan mask.
        label.textColor = .ows_white

        return label
    }()

    private lazy var uploadPhotoButton: UIButton = {
        let button = OWSRoundedButton { [weak self] in
            self?.didTapUploadPhotoButton()
        }

        button.ows_contentEdgeInsets = UIEdgeInsets(margin: 14)

        // Always use dark theming since it sits over the scan mask.
        button.setTemplateImageName(
            Theme.iconName(.buttonPhotoLibrary),
            tintColor: .ows_white
        )
        button.backgroundColor = .ows_whiteAlpha20

        return button
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
        view.addSubview(uploadPhotoButton)

        scanViewController.view.autoPinEdgesToSuperviewEdges()
        instructionsWrapperView.autoPinEdges(toSuperviewSafeAreaExcludingEdge: .bottom)

        uploadPhotoButton.autoSetDimensions(to: .square(52))
        uploadPhotoButton.autoHCenterInSuperview()
        uploadPhotoButton.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 16)

        themeDidChange()
        contentSizeCategoryDidChange()
    }

    override func contentSizeCategoryDidChange() {
        instructionsLabel.font = .dynamicTypeBody2
    }

    // MARK: Actions

    func didTapUploadPhotoButton() {
        let imagePickerViewController = ImagePickerGridController()
        imagePickerViewController.delegate = self
        imagePickerViewController.dataSource = self

        let imagePickerNavController = OWSNavigationController(
            rootViewController: imagePickerViewController
        )

        presentFormSheet(imagePickerNavController, animated: true)
    }
}

// MARK: - Scan delegate

extension UsernameLinkScanQRCodeViewController: QRCodeScanOrPickDelegate {
    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?
    ) -> QRCodeScanOutcome {
        guard let qrCodeString else {
            UsernameLogger.shared.error("Unexpectedly missing QR code string!")
            return .continueScanning
        }

        guard
            let scannedUrl = URL(string: qrCodeString),
            let scannedUsernameLink = Usernames.UsernameLink(usernameLinkUrl: scannedUrl)
        else {
            UsernameLogger.shared.error(
                "Failed to create username link from scanned QR code!"
            )
            return .continueScanning
        }

        guard let scanDelegate else {
            UsernameLogger.shared.error("Missing scan delegate!")
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
