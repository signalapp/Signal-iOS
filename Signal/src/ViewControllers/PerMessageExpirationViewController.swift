//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class PerMessageExpirationViewController: OWSViewController {

    // MARK: - Dependencies

    static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Properties

    private let interaction: TSInteraction
    private let attachmentStream: TSAttachmentStream

    // MARK: - Initializers

    required init(interaction: TSInteraction, attachmentStream: TSAttachmentStream) {
        self.interaction = interaction
        self.attachmentStream = attachmentStream

        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    private typealias Presentation = (interaction: TSInteraction, attachmentStream: TSAttachmentStream)

    @objc
    public class func tryToPresent(interaction: TSInteraction,
                                   from fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard let presentation = loadPresentation(interaction: interaction) else {
            owsFailDebug("Could not present interaction")
            return
        }

        let view = PerMessageExpirationViewController(interaction: presentation.interaction, attachmentStream: presentation.attachmentStream)
        fromViewController.present(view, animated: true)
    }

    private class func loadPresentation(interaction: TSInteraction) -> Presentation? {
        AssertIsOnMainThread()

        return databaseStorage.uiReadReturningResult { transaction in
            guard let interactionId = interaction.uniqueId else {
                return nil
            }
            guard let message = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) as? TSMessage else {
                return nil
            }
            guard !message.perMessageExpirationHasExpired else {
                return nil
            }
            guard let attachmentId = message.attachmentIds.firstObject as? String else {
                return nil
            }
            guard let attachmentStream = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) as? TSAttachmentStream else {
                return nil
            }
            return (interaction: message, attachmentStream: attachmentStream)
        }
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

        var mediaAspectRatio: CGFloat
        var mediaView: UIView
        if let mediaTuple = buildMediaView() {
            mediaAspectRatio = mediaTuple.aspectRatio
            mediaView = mediaTuple.mediaView
        } else {
            mediaAspectRatio = 1
            mediaView = UIView()
            mediaView.backgroundColor = Theme.darkThemeOffBackgroundColor
        }

        contentView.addSubview(mediaView)
        _ = contentView.applyScaleAspectFitLayout(subview: mediaView, aspectRatio: mediaAspectRatio)

        let hMargin: CGFloat = 16

        let dismissButton = OWSButton(imageName: "x-24", tintColor: Theme.darkThemePrimaryColor)
        dismissButton.addTarget(self, action: #selector(dismissButtonPressed(sender:)), for: .touchUpInside)
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 20, leading: hMargin, bottom: 20, trailing: hMargin)
        view.addSubview(dismissButton)
        dismissButton.autoPinEdge(.leading, to: .leading, of: mediaView)
        dismissButton.autoPinEdge(.top, to: .top, of: mediaView)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                         action: #selector(rootViewWasTapped)))

        setupDatabaseObservation()
    }

    private func buildMediaView() -> (mediaView: UIView, aspectRatio: CGFloat)? {
        guard attachmentStream.isValidVisualMedia else {
            return nil
        }
        guard let filePath = attachmentStream.originalFilePath else {
            owsFailDebug("Attachment missing file path.")
            return nil
        }

        if attachmentStream.isAnimated || attachmentStream.contentType == OWSMimeTypeImageWebp {
            guard let image = YYImage(contentsOfFile: filePath) else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            guard image.size.width > 0,
                image.size.height > 0 else {
                    owsFailDebug("Attachment has invalid size.")
                    return nil
            }
            let aspectRatio = image.size.width / image.size.height

            let animatedImageView = YYAnimatedImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            animatedImageView.contentMode = .scaleAspectFit
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            animatedImageView.layer.minificationFilter = .trilinear
            animatedImageView.layer.magnificationFilter = .trilinear
            animatedImageView.image = image
            return (mediaView: animatedImageView, aspectRatio: aspectRatio)
        } else if attachmentStream.isImage {
            guard let image = UIImage(contentsOfFile: filePath) else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            guard image.size.width > 0,
                image.size.height > 0 else {
                    owsFailDebug("Attachment has invalid size.")
                    return nil
            }
            let aspectRatio = image.size.width / image.size.height

            let imageView = UIImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            imageView.contentMode = .scaleAspectFit
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            imageView.layer.minificationFilter = .trilinear
            imageView.layer.magnificationFilter = .trilinear
            imageView.image = image
            return (mediaView: imageView, aspectRatio: aspectRatio)
        } else {
            owsFailDebug("Unexpected content type: \(attachmentStream.contentType).")
            return nil
        }
    }

    func setupDatabaseObservation() {
        if FeatureFlags.useGRDB {
            guard let observer = databaseStorage.grdbStorage.conversationViewDatabaseObserver else {
                owsFailDebug("observer was unexpectedly nil")
                return
            }
            observer.appendSnapshotDelegate(self)
        } else {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(uiDatabaseDidUpdate),
                                                   name: .OWSUIDatabaseConnectionDidUpdateExternally,
                                                   object: OWSPrimaryStorage.shared().dbNotificationObject)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(uiDatabaseDidUpdate),
                                                   name: .OWSUIDatabaseConnectionDidUpdate,
                                                   object: OWSPrimaryStorage.shared().dbNotificationObject)
        }
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

    private func dismissIfExpired() {
        AssertIsOnMainThread()

        let shouldDismiss: Bool = databaseStorage.uiReadReturningResult { transaction in
            guard let uniqueId = self.interaction.uniqueId else {
                return true
            }
            guard let message = TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction) as? TSMessage else {
                return true
            }
            return message.perMessageExpirationHasExpired
        }

        if shouldDismiss {
            self.dismiss(animated: true)
        }
    }

    // MARK: - Events

    @objc internal func uiDatabaseDidUpdate(notification: NSNotification) {
        AssertIsOnMainThread()

        Logger.debug("")

        dismissIfExpired()
    }

    @objc
    func applicationWillEnterForeground() throws {
        AssertIsOnMainThread()

        Logger.debug("")

        dismissIfExpired()
    }

    @objc
    private func dismissButtonPressed(sender: UIButton) {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }

    @objc
    func rootViewWasTapped(sender: UIGestureRecognizer) {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }

}

// MARK: -

extension PerMessageExpirationViewController: ConversationViewDatabaseSnapshotDelegate {
    public func conversationViewDatabaseSnapshotWillUpdate() {
        dismissIfExpired()
    }

    public func conversationViewDatabaseSnapshotDidUpdate(transactionChanges: ConversationViewDatabaseTransactionChanges) {
        dismissIfExpired()
    }

    public func conversationViewDatabaseSnapshotDidUpdateExternally() {
        dismissIfExpired()
    }

    public func conversationViewDatabaseSnapshotDidReset() {
        dismissIfExpired()
    }
}
