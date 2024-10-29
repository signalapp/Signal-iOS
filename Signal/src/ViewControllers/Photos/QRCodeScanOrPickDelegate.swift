//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalUI
import SignalServiceKit

struct ImagePickerAttachment {
    let phAsset: PHAsset
    let fetcher: () async throws -> SignalAttachment
}

enum QRCodeImagePickerError: Error {
    case noAttachmentImage
    case ciDetectorError
    case noQRCodeFound
}

protocol QRCodeScanOrPickDelegate: QRCodeScanDelegate, ImagePickerGridControllerDelegate, ImagePickerGridControllerDataSource {
    var selectedAttachment: ImagePickerAttachment? { get set }
}

extension QRCodeScanOrPickDelegate {

    // MARK: QRCodeScanDelegate

    func didTapUploadPhotoButton(_ qrCodeScanViewController: QRCodeScanViewController) {
        let imagePickerViewController = ImagePickerGridController()
        imagePickerViewController.delegate = self
        imagePickerViewController.dataSource = self

        let imagePickerNavController = OWSNavigationController(
            rootViewController: imagePickerViewController
        )

        qrCodeScanViewController.presentFormSheet(imagePickerNavController, animated: true)
    }

    // MARK: ImagePickerGridControllerDelegate

    func imagePickerDidComplete(_ imagePicker: ImagePickerGridController) {
        guard let selectedAttachment else { return }

        Task {
            do {
                let attachment = try await selectedAttachment.fetcher()

                guard
                    let image = attachment.image(),
                    let ciImage = CIImage(image: image)
                else {
                    throw QRCodeImagePickerError.noAttachmentImage
                }

                guard let qrCodeDetector = CIDetector(
                    ofType: CIDetectorTypeQRCode,
                    context: nil,
                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
                ) else {
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

                DispatchQueue.main.async {
                    imagePicker.dismiss(animated: true) {
                        self.qrCodeScanViewScanned(
                            qrCodeData: nil,
                            qrCodeString: qrCodeMessageString
                        )
                    }
                }
            } catch {
                Logger.error("\(error)")
                OWSActionSheets.showErrorAlert(
                    message: CommonStrings.somethingWentWrongError,
                    fromViewController: imagePicker
                )
            }
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
        selectedAttachment = ImagePickerAttachment(
            phAsset: asset,
            fetcher: attachmentPromise.awaitable
        )
    }

    func imagePicker(
        _ imagePicker: ImagePickerGridController,
        didDeselectAsset asset: PHAsset
    ) {
        // Because we only ever have one selected item, we don't need to check
        // if the deselected asset matches the one we had previously selected.
        selectedAttachment = nil
    }

    func imagePickerDidTryToSelectTooMany(
        _ imagePicker: ImagePickerGridController
    ) {
        // The selection will fail, and there's no need to show an error.
    }

    // MARK: ImagePickerGridControllerDataSource

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool {
        selectedAttachment?.phAsset == asset
    }

    func imagePickerCanSelectMoreItems(_ imagePicker: ImagePickerGridController) -> Bool {
        selectedAttachment == nil
    }

    var numberOfMediaItems: Int {
        selectedAttachment == nil ? 0 : 1
    }
}
