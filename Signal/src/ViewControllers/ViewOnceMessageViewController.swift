//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class ViewOnceMessageViewController: OWSViewController {

    class Content {
        let messageId: String
        let filePath: String
        // The content is an animated image (GIF or WEBP)
        // if true, a still image otherwise.
        // TODO: We could eventually support video.
        let isAnimated: Bool

        init(messageId: String,
             filePath: String,
             isAnimated: Bool) {
            self.messageId = messageId
            self.filePath = filePath
            self.isAnimated = isAnimated
        }

        deinit {
            Logger.verbose("Cleaning up temp file")

            let filePath = self.filePath
            DispatchQueue.global().async {
                OWSFileSystem.deleteFile(filePath)
            }
        }
    }

    // MARK: - Dependencies

    static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Properties

    private let content: Content

    // MARK: - Initializers

    required init(content: Content) {
        self.content = content

        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    public class func tryToPresent(interaction: TSInteraction,
                                   from fromViewController: UIViewController) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { (modal) in
                                                        DispatchQueue.main.async {
                                                            let content: Content? = loadContentForPresentation(interaction: interaction)

                                                            modal.dismiss(completion: {
                                                                guard let content = content else {
                                                                    owsFailDebug("Could not present interaction")
                                                                    // TODO: Show an alert.
                                                                    return
                                                                }

                                                                let view = ViewOnceMessageViewController(content: content)
                                                                fromViewController.present(view, animated: true)
                                                            })
                                                        }
        }
    }

    private class func loadContentForPresentation(interaction: TSInteraction) -> Content? {
        var content: Content?
        // The only way to ensure that the content is never presented
        // more than once is to do a bunch of work (include file system
        // activity) inside a write transaction, which normally
        // wouldn't be desirable.
        databaseStorage.write { transaction in
            let interactionId = interaction.uniqueId
            guard let message = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) as? TSMessage else {
                return
            }
            guard message.isViewOnceMessage else {
                owsFailDebug("Unexpected message.")
                return
            }
            let messageId = message.uniqueId

            // Auto-complete the message before going any further.
            ViewOnceMessages.completeIfNecessary(message: message, transaction: transaction)
            guard !message.isViewOnceComplete else {
                return
            }

            // We should _always_ mark the message as complete,
            // even if the message is malformed, or if we fail
            // to do the "file system dance" below, etc.
            // and we fail to present the message content.
            defer {
                // This will eliminate the renderable content of the message.
                ViewOnceMessages.markAsComplete(message: message, sendSyncMessages: true, transaction: transaction)
            }

            guard let attachmentId = message.attachmentIds.first else {
                return
            }
            guard let attachmentStream = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) as? TSAttachmentStream else {
                return
            }
            guard attachmentStream.isValidVisualMedia else {
                return
            }
            let contentType = attachmentStream.contentType
            guard contentType.count > 0 else {
                owsFailDebug("Missing content type.")
                    return
            }
            let isAnimated: Bool
            if attachmentStream.isAnimated || contentType == OWSMimeTypeImageWebp {
                isAnimated = true
            } else if attachmentStream.isImage {
                isAnimated = false
            } else {
                owsFailDebug("Unexpected content type.")
                return
            }

            // To ensure that we never show the content more than once,
            // we mark the "view-once message" as complete _before_
            // presenting its contents.  A side effect of this is that
            // its renderable content is deleted.  We need the renderable
            // content to present it.  Therefore, we do a little dance:
            //
            // * Move the attachment file to a temporary file.
            // * Create an empty placeholder file in the old attachment
            //   file's location so that TSAttachmentStream's invariant
            //   of always corresponding to an underlying file on disk
            //   remains true.
            // * Delete the temporary file when this view is dismissed.
            // * If the app terminates at any step during this process,
            //   either: a) the file wasn't moved, the message wasn't
            //   marked as complete and the content wasn't displayed
            //   so the user can try again after relaunch.
            //   b) the file was moved and will be cleaned up on next
            //   launch like any other temp file if it hasn't been
            //   deleted already.
            guard let originalFilePath = attachmentStream.originalFilePath else {
                owsFailDebug("Attachment missing file path.")
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: originalFilePath) else {
                owsFailDebug("Missing temp file.")
                return
            }
            guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: contentType) else {
                owsFailDebug("Couldn't determine file extension.")
                return
            }
            let tempFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
            guard OWSFileSystem.fileOrFolderExists(atPath: originalFilePath) else {
                owsFailDebug("Missing attachment file.")
                return
            }
            guard !OWSFileSystem.fileOrFolderExists(atPath: tempFilePath) else {
                owsFailDebug("Temp file unexpectedly already exists.")
                return
            }
            // Move the attachment to the temp file.
            // A copy would be much more expensive.
            guard OWSFileSystem.moveFilePath(originalFilePath, toFilePath: tempFilePath) else {
                owsFailDebug("Couldn't move file.")
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: tempFilePath) else {
                owsFailDebug("Missing temp file.")
                return
            }
            // This should be redundant since temp files are
            // created inside the per-launch temp folder
            // and should inherit protection from it.
            guard OWSFileSystem.protectFileOrFolder(atPath: tempFilePath) else {
                owsFailDebug("Couldn't protect temp file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }
            // Create new empty "placeholder file at the attachment's old
            //  location, since the attachment model should always correspond
            // to an underlying file on disk.
            guard OWSFileSystem.ensureFileExists(originalFilePath) else {
                owsFailDebug("Couldn't create placeholder file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: originalFilePath) else {
                owsFailDebug("Missing placeholder file.")
                OWSFileSystem.deleteFile(tempFilePath)
                return
            }

            content = Content(messageId: messageId,
                              filePath: tempFilePath,
                              isAnimated: isAnimated)
        }
        return content
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.ows_black

        self.modalPresentationStyle = .overFullScreen

        let contentView = UIView()
        view.addSubview(contentView)
        contentView.autoPinWidthToSuperview()
        contentView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        contentView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        let defaultMediaView = UIView()
        defaultMediaView.backgroundColor = Theme.darkThemeOffBackgroundColor
        let mediaView = buildMediaView() ?? defaultMediaView

        contentView.addSubview(mediaView)
        mediaView.autoPinEdgesToSuperviewEdges()

        let hMargin: CGFloat = 16
        let vMargin: CGFloat = 20
        let controlSize: CGFloat = 24
        let controlSpacing: CGFloat = 20
        let controlsWidth = controlSize * 2 + controlSpacing + hMargin * 2
        let controlsHeight = controlSize + vMargin * 2
        mediaView.autoSetDimension(.width, toSize: controlsWidth, relation: .greaterThanOrEqual)
        mediaView.autoSetDimension(.height, toSize: controlsHeight, relation: .greaterThanOrEqual)

        let dismissButton = OWSButton(imageName: "x-24", tintColor: Theme.darkThemePrimaryColor) { [weak self] in
            self?.dismissButtonPressed()
        }
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: vMargin, leading: hMargin, bottom: vMargin, trailing: hMargin)
        view.addSubview(dismissButton)
        dismissButton.autoPinEdge(.leading, to: .leading, of: mediaView)
        dismissButton.autoPinEdge(.top, to: .top, of: mediaView)
        dismissButton.setShadow(opacity: 0.66)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                         action: #selector(rootViewWasTapped)))
        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(rootViewWasSwiped))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)

        setupDatabaseObservation()
    }

    private func buildMediaView() -> UIView? {
        let filePath = content.filePath

        if content.isAnimated {
            guard let image = YYImage(contentsOfFile: filePath) else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            guard image.size.width > 0,
                image.size.height > 0 else {
                    owsFailDebug("Attachment has invalid size.")
                    return nil
            }
            let animatedImageView = YYAnimatedImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            animatedImageView.contentMode = .scaleAspectFit
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            animatedImageView.layer.minificationFilter = .trilinear
            animatedImageView.layer.magnificationFilter = .trilinear
            animatedImageView.layer.allowsEdgeAntialiasing = true
            animatedImageView.image = image
            return animatedImageView
        } else {
            guard let image = UIImage(contentsOfFile: filePath) else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            guard image.size.width > 0,
                image.size.height > 0 else {
                    owsFailDebug("Attachment has invalid size.")
                    return nil
            }

            let imageView = UIImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            imageView.contentMode = .scaleAspectFit
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            imageView.layer.minificationFilter = .trilinear
            imageView.layer.magnificationFilter = .trilinear
            imageView.layer.allowsEdgeAntialiasing = true
            imageView.image = image
            return imageView
        }
    }

    func setupDatabaseObservation() {
        databaseStorage.add(databaseStorageObserver: self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
    }

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Video

    // Once open, this view only dismisses if the message is deleted
    // (e.g. by per-conversation expiration).
    private func dismissIfRemoved() {
        AssertIsOnMainThread()

        let shouldDismiss: Bool = databaseStorage.uiReadReturningResult { transaction in
            let uniqueId = self.content.messageId
            guard TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil else {
                return true
            }
            return false
        }

        if shouldDismiss {
            self.dismiss(animated: true)
        }
    }

    // MARK: - Events

    @objc
    func applicationWillEnterForeground() throws {
        AssertIsOnMainThread()

        Logger.debug("")

        dismissIfRemoved()
    }

    @objc
    private func dismissButtonPressed() {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }

    @objc
    func rootViewWasTapped(sender: UIGestureRecognizer) {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }

    @objc
    func rootViewWasSwiped(sender: UIGestureRecognizer) {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }
}

// MARK: -

extension ViewOnceMessageViewController: SDSDatabaseStorageObserver {
    func databaseStorageDidUpdate(change: SDSDatabaseStorageChange) {
        AssertIsOnMainThread()

        dismissIfRemoved()
    }

    func databaseStorageDidUpdateExternally() {
        AssertIsOnMainThread()

        dismissIfRemoved()
    }

    func databaseStorageDidReset() {
        AssertIsOnMainThread()

        dismissIfRemoved()
    }
}
