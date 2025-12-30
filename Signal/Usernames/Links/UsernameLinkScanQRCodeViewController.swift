//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PhotosUI
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
            showUploadPhotoButton: true,
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
            comment: "Text providing instructions on how to use the username link QR code scanning.",
        )

        // Always use dark theme since it sits over the scan mask.
        label.textColor = .ows_white

        return label
    }()

    // MARK: - Lifecycle

    var navbarBackgroundColorOverride: UIColor? {
        return OWSTableViewController2.tableBackgroundColor(
            isUsingPresentedStyle: true,
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

        scanViewController.view.autoPinEdgesToSuperviewEdges()
        instructionsWrapperView.autoPinEdges(toSuperviewSafeAreaExcludingEdge: .bottom)

        themeDidChange()
        contentSizeCategoryDidChange()
    }

    override func contentSizeCategoryDidChange() {
        instructionsLabel.font = .dynamicTypeSubheadline
    }

    // MARK: Actions
}

// MARK: - Scan delegate

extension UsernameLinkScanQRCodeViewController: QRCodeScanDelegate {
    var shouldShowUploadPhotoButton: Bool { true }

    func didTapUploadPhotoButton(_ qrCodeScanViewController: QRCodeScanViewController) {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        self.present(picker, animated: true)
    }

    func qrCodeScanViewScanned(
        qrCodeData: Data?,
        qrCodeString: String?,
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
                "Failed to create username link from scanned QR code!",
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
        _ qrCodeScanViewController: QRCodeScanViewController,
    ) {
        dismiss(animated: true)
    }
}

extension UsernameLinkScanQRCodeViewController: PHPickerViewControllerDelegate {
    private enum QRCodeImagePickerError: Error {
        case noAttachmentImage
        case ciDetectorError
        case noQRCodeFound
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let selectedItem = results.first else {
            picker.dismiss(animated: true)
            return
        }

        Task { @MainActor in
            async let dismiss: Void = { @MainActor () async -> Void in
                await withCheckedContinuation { continuation in
                    picker.dismiss(animated: true) {
                        continuation.resume()
                    }
                }
            }()

            do {
                let attachment = try await TypedItemProvider.buildVisualMediaAttachment(forItemProvider: selectedItem.itemProvider)
                guard
                    let image = attachment.rawValue.image(),
                    let ciImage = CIImage(image: image)
                else {
                    throw QRCodeImagePickerError.noAttachmentImage
                }

                guard
                    let qrCodeDetector = CIDetector(
                        ofType: CIDetectorTypeQRCode,
                        context: nil,
                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh],
                    )
                else {
                    throw QRCodeImagePickerError.ciDetectorError
                }

                let detectedFeatures = qrCodeDetector.features(in: ciImage)

                guard
                    detectedFeatures.count == 1,
                    let qrCodeFeature = detectedFeatures.first as? CIQRCodeFeature,
                    let qrCodeMessageString = qrCodeFeature.messageString
                else {
                    throw QRCodeImagePickerError.noQRCodeFound
                }

                _ = await dismiss

                _ = self.qrCodeScanViewScanned(
                    qrCodeData: nil,
                    qrCodeString: qrCodeMessageString,
                )
            } catch {
                UsernameLogger.shared.error("Error building attachment for QC code scan: \(error)")
                _ = await dismiss
                OWSActionSheets.showErrorAlert(
                    message: CommonStrings.somethingWentWrongError,
                    fromViewController: self,
                )
            }
        }
    }
}
