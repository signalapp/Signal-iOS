//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import PureLayout
import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol UsernameLinkScanDelegate: AnyObject {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink)
}

class UsernameLinkScanQRCodeViewController: OWSViewController, OWSNavigationChildController {
    /// Represents an item selected from the image picker, intended to contain a
    /// username link QR code.
    ///
    /// The image picker returns us a ``PHAsset`` and a convenient
    /// ``SignalAttachment`` promise whenever an item is selected. It's a little
    /// clunky, but rather than dealing with loading the asset we can use the
    /// attachment promise to get the image, so we hold onto both.
    private struct SelectedPickerItem {
        let phAsset: PHAsset
        let attachmentPromise: Promise<SignalAttachment>
    }

    private var selectedPickerItem: SelectedPickerItem?

    weak var scanDelegate: UsernameLinkScanDelegate?

    init(scanDelegate: UsernameLinkScanDelegate) {
        self.scanDelegate = scanDelegate

        super.init()
    }

    private var context: ViewControllerContext { .shared }

    // MARK: - Views

    private lazy var scanViewController = {
        // Because we're overlaying things onto the scan view, the centered mask
        // window looks a little off. Shifting it up by 16pt looks cleaner and
        // matches the designs better.
        let scanMaskWindowOffset = CGPoint(x: 0, y: -16)

        let scanViewController = QRCodeScanViewController(
            appearance: .masked(maskWindowOffset: scanMaskWindowOffset)
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

        button.contentEdgeInsets = UIEdgeInsets(margin: 14)

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

        scanViewController.view.autoPinEdgesToSuperviewSafeArea()
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

    private func didTapUploadPhotoButton() {
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

extension UsernameLinkScanQRCodeViewController: QRCodeScanDelegate {
    func qrCodeScanViewScanned(
        _ qrCodeScanViewController: QRCodeScanViewController,
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

// MARK: - Image Picker

extension UsernameLinkScanQRCodeViewController: ImagePickerGridControllerDelegate {
    func imagePickerDidComplete(_ imagePicker: ImagePickerGridController) {
        guard let selectedPickerItem = self.selectedPickerItem else {
            return
        }

        firstly(on: context.schedulers.sync) { () -> Promise<Usernames.UsernameLink> in
            return self.parseUsernameLinkFromAttachment(
                attachmentPromise: selectedPickerItem.attachmentPromise
            )
        }
        .done(on: context.schedulers.main) { usernameLink in
            guard let scanDelegate = self.scanDelegate else {
                throw OWSAssertionError("Missing scan delegate!")
            }

            // Our delegate will handle dismissing us, since in practice we're
            // not the only controller that needs dismissing.
            scanDelegate.usernameLinkScanned(usernameLink)
        }
        .catch(on: context.schedulers.main) { error in
            OWSActionSheets.showErrorAlert(
                message: CommonStrings.somethingWentWrongError,
                fromViewController: imagePicker
            )
        }
    }

    func imagePickerDidCancel(_ imagePicker: ImagePickerGridController) {
        imagePicker.dismiss(animated: true)
    }

    func imagePicker(
        _ imagePicker: ImagePickerGridController,
        didSelectAsset asset: PHAsset,
        attachmentPromise: Promise<SignalAttachment>
    ) {
        selectedPickerItem = SelectedPickerItem(
            phAsset: asset,
            attachmentPromise: attachmentPromise
        )
    }

    func imagePicker(
        _ imagePicker: ImagePickerGridController,
        didDeselectAsset asset: PHAsset
    ) {
        // Because we only ever have one selected item, we don't need to check
        // if the deselected asset matches the one we had previously selected.
        selectedPickerItem = nil
    }

    func imagePickerDidTryToSelectTooMany(
        _ imagePicker: ImagePickerGridController
    ) {
        // The selection will fail, and there's no need to show an error.
    }
}

extension UsernameLinkScanQRCodeViewController: ImagePickerGridControllerDataSource {
    func imagePicker(
        _ imagePicker: ImagePickerGridController,
        isAssetSelected asset: PHAsset
    ) -> Bool {
        return selectedPickerItem?.phAsset == asset
    }

    func imagePickerCanSelectMoreItems(
        _ imagePicker: ImagePickerGridController
    ) -> Bool {
        return selectedPickerItem == nil
    }

    var numberOfMediaItems: Int {
        return selectedPickerItem == nil ? 0 : 1
    }
}

private extension UsernameLinkScanQRCodeViewController {
    func parseUsernameLinkFromAttachment(
        attachmentPromise: Promise<SignalAttachment>
    ) -> Promise<Usernames.UsernameLink> {
        struct AttachmentToUsernameLinkFailedError: Error {}

        return firstly(on: context.schedulers.sync) { () -> Promise<SignalAttachment> in
            return attachmentPromise
        }
        .map(on: context.schedulers.sync) { attachment throws -> Usernames.UsernameLink in
            guard let imageFromAttachment = attachment.image() else {
                UsernameLogger.shared.error("Unexpectedly failed to get image from attachment!")
                throw AttachmentToUsernameLinkFailedError()
            }

            guard let usernameLink = self.parseImageForQRCode(
                image: imageFromAttachment
            ) else {
                UsernameLogger.shared.warn("Image did not contain username link QR code!")
                throw AttachmentToUsernameLinkFailedError()
            }

            return usernameLink
        }
    }

    private func parseImageForQRCode(image: UIImage) -> Usernames.UsernameLink? {
        guard let qrCodeDetector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            UsernameLogger.shared.error("Failed to create QR code detector!")
            return nil
        }

        guard let ciImage = CIImage(image: image) else {
            UsernameLogger.shared.warn("Failed to create CIImage from image...")
            return nil
        }

        let detectedFeatures = qrCodeDetector.features(in: ciImage)

        guard
            detectedFeatures.count == 1,
            let qrCodeFeature = detectedFeatures.first as? CIQRCodeFeature
        else {
            UsernameLogger.shared.warn("Failed to detect QR code feature... Feature count: \(detectedFeatures.count)")
            return nil
        }

        guard
            let qrCodeMessageString = qrCodeFeature.messageString,
            let qrCodeMessageUrl = URL(string: qrCodeMessageString)
        else {
            UsernameLogger.shared.warn("Failed to get message URL from QR code...")
            return nil
        }

        guard let usernameLink = Usernames.UsernameLink(
            usernameLinkUrl: qrCodeMessageUrl
        ) else {
            UsernameLogger.shared.warn("Failed to construct username link from URL...")
            return nil
        }

        return usernameLink
    }
}
