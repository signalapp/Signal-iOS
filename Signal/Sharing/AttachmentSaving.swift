//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI

enum AttachmentSaving {
    /// Save the given attachments to the photo library.
    ///
    /// - Note
    /// Only attachments representing media that can be saved to the photo
    /// library will be saved. Others will be ignored.
    static func saveToPhotoLibrary(
        referencedAttachmentStreams: [ReferencedAttachmentStream],
    ) {
        let (assetCreationRequests, _) = referencedAttachmentStreams.reduce(
            into: (requests: [PHAssetCreationRequestType](), filenames: Set<String>()),
        ) { result, referencedAttachmentStream in
            let reference = referencedAttachmentStream.reference
            let attachmentStream = referencedAttachmentStream.attachmentStream

            switch attachmentStream.contentType {
            case .invalid, .audio, .file:
                return
            case .image, .animatedImage, .video:
                break
            }

            let filename = uniqueFilename(
                sourceFilename: reference.sourceFilename,
                existingFilenames: &result.filenames,
            )

            let decryptedFileUrl: URL
            do {
                decryptedFileUrl = try attachmentStream.makeDecryptedCopy(
                    filename: filename,
                )
            } catch let error {
                owsFailDebug("Failed to save decrypted copy of attachment for photo library! \(error)")
                return
            }

            switch attachmentStream.contentType {
            case .invalid, .audio, .file:
                owsFail("Impossible: checked above!")
            case .image, .animatedImage:
                result.requests.append(.imageTempFile(tmpFileUrl: decryptedFileUrl))
            case .video:
                result.requests.append(.videoTempFile(tmpFileUrl: decryptedFileUrl))
            }
        }

        _confirmAndSaveToPhotoLibrary(assetCreationRequests: assetCreationRequests)
    }

    /// Save the given image to the photo library.
    static func saveToPhotoLibrary(image: UIImage) {
        _confirmAndSaveToPhotoLibrary(assetCreationRequests: [.image(image)])
    }

    private static func _confirmAndSaveToPhotoLibrary(
        assetCreationRequests: [PHAssetCreationRequestType],
    ) {
        let fromViewController = CurrentAppContext().frontmostViewController()!

        let db = DependenciesBridge.shared.db
        let preferenceStore = PreferenceStore()

        let shouldShowActionSheet = db.read { preferenceStore.shouldShowSaveMediaActionSheet(tx: $0) }
        if shouldShowActionSheet {
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "ATTACHMENT_SAVING_ACTION_SHEET_TITLE",
                    comment: "Title for an action sheet asking users about saving attachments. 'Photos' is the name of the default Photos app on iOS, and should be localized as that app's name.",
                ),
                message: OWSLocalizedString(
                    "ATTACHMENT_SAVING_ACTION_SHEET_MESSAGE",
                    comment: "Message for an action sheet asking users about saving attachments. 'Photos' is the name of the default Photos app on iOS, and should be localized as that app's name.",
                ),
            )

            let saveAction = ActionSheetAction(title: OWSLocalizedString(
                "ATTACHMENT_SAVING_ACTION_SHEET_ACTION_SAVE",
                comment: "Title for an action in an action sheet that will save attachments to the device's Photos app.",
            )) { _ in
                _saveToPhotoLibrary(
                    assetCreationRequests: assetCreationRequests,
                    fromViewController: fromViewController,
                )
            }

            let saveAndDontShowAgainAction = ActionSheetAction(title: OWSLocalizedString(
                "ATTACHMENT_SAVING_ACTION_SHEET_ACTION_SAVE_AND_DONT_SHOW_AGAIN",
                comment: "Title for an action in an action sheet that will save attachments to the device's Photos app, and disable the action sheet in the future.",
            )) { _ in
                db.write { preferenceStore.disableShowingSaveMediaActionSheet(tx: $0) }

                _saveToPhotoLibrary(
                    assetCreationRequests: assetCreationRequests,
                    fromViewController: fromViewController,
                )
            }

            actionSheet.addAction(saveAction)
            actionSheet.addAction(saveAndDontShowAgainAction)
            actionSheet.addAction(.cancel)
            fromViewController.presentActionSheet(actionSheet)
        } else {
            _saveToPhotoLibrary(
                assetCreationRequests: assetCreationRequests,
                fromViewController: fromViewController,
            )
        }
    }

    private static func _saveToPhotoLibrary(
        assetCreationRequests: [PHAssetCreationRequestType],
        fromViewController: UIViewController,
    ) {
        Task { @MainActor in
            let isGranted = await fromViewController.ows_askForMediaLibraryPermissions(for: .addOnly)
            guard isGranted else {
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for assetCreationRequest in assetCreationRequests {
                        switch assetCreationRequest {
                        case .image(let image):
                            PHAssetCreationRequest.creationRequestForAsset(from: image)
                        case .imageTempFile(let fileUrl):
                            PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileUrl)
                        case .videoTempFile(let fileUrl):
                            PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileUrl)
                        }
                    }
                }

                Logger.info("Saved attachments to photo library.")

                ToastController(text: OWSLocalizedString(
                    "ATTACHMENT_SAVING_SUCCESS_MESSAGE",
                    comment: "Message shown in a toast after user successfully saves attachments to Photos. 'Photos' is the name of the default Photos app on iOS, and should be localized as that app's name.",
                )).presentToastView(
                    from: .bottom,
                    of: fromViewController.view,
                    inset: 40,
                )
            } catch {
                Logger.error("Failed to save attachments to photo library: \(error)")

                OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                    "ATTACHMENT_SAVING_FAILURE_MESSAGE",
                    comment: "Message shown in an action sheet after user fails to save attachments to Photos. 'Photos' is the name of the default Photos app on iOS, and should be localized as that app's name.",
                ))
            }

            // Best-effort attempt to delete any temp files, now that we're
            // done with them. They'll be cleared eventually regardless.
            for tmpFileUrl in assetCreationRequests.compactMap(\.tmpFileUrl) {
                try? OWSFileSystem.deleteFile(url: tmpFileUrl)
            }
        }
    }

    // MARK: -

    static func uniqueFilename(
        sourceFilename: String?,
        existingFilenames: inout Set<String>,
    ) -> String? {
        if
            let sourceFilename,
            existingFilenames.contains(sourceFilename)
        {
            // Avoid source filename collisions.
            let pathExtension = (sourceFilename as NSString).pathExtension
            let normalizedFilename = (sourceFilename as NSString)
                .deletingPathExtension
                .trimmingCharacters(in: .whitespaces)

            var i = 0
            while true {
                i += 1
                var newSourceFilename = normalizedFilename + "_\(i)"
                newSourceFilename = (newSourceFilename as NSString).appendingPathExtension(pathExtension) ?? newSourceFilename
                if !existingFilenames.contains(newSourceFilename) {
                    existingFilenames.insert(newSourceFilename)
                    return newSourceFilename
                }
            }
        } else {
            _ = sourceFilename.map { existingFilenames.insert($0) }
            return sourceFilename
        }
    }

    // MARK: -

    private enum PHAssetCreationRequestType {
        case image(UIImage)
        case imageTempFile(tmpFileUrl: URL)
        case videoTempFile(tmpFileUrl: URL)

        var tmpFileUrl: URL? {
            return switch self {
            case .image: nil
            case .imageTempFile(let tmpFileUrl): tmpFileUrl
            case .videoTempFile(let tmpFileUrl): tmpFileUrl
            }
        }
    }

    // MARK: -

    private struct PreferenceStore {
        private enum Keys: String {
            case shouldShowSaveMediaActionSheet
        }

        private let kvStore: KeyValueStore

        init() {
            kvStore = KeyValueStore(collection: "AttachmentSaving")
        }

        func shouldShowSaveMediaActionSheet(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Keys.shouldShowSaveMediaActionSheet.rawValue, transaction: tx) ?? true
        }

        func disableShowingSaveMediaActionSheet(tx: DBWriteTransaction) {
            kvStore.setBool(false, key: Keys.shouldShowSaveMediaActionSheet.rawValue, transaction: tx)
        }
    }
}
