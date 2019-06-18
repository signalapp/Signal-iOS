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

    private let message: TSMessage
    private let attachmentStream: TSAttachmentStream

    private let progressView = CircularProgressView(thickness: 0.15)

    private var timer: Timer?

    // MARK: - Initializers

    required init(message: TSMessage, attachmentStream: TSAttachmentStream) {
        self.message = message
        self.attachmentStream = attachmentStream

        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    private typealias Presentation = (message: TSMessage, attachmentStream: TSAttachmentStream)

    @objc
    public class func tryToPresent(interaction: TSInteraction,
                                   from fromViewController: UIViewController) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { (modal) in
                                                        DispatchQueue.main.async {
                                                            let presentation: Presentation? = loadPresentation(interaction: interaction)

                                                            modal.dismiss(completion: {
                                                                guard let presentation = presentation else {
                                                                    owsFailDebug("Could not present interaction")
                                                                    // TODO: Show an alert.
                                                                    return
                                                                }

                                                                let view = PerMessageExpirationViewController(message: presentation.message,
                                                                                                              attachmentStream: presentation.attachmentStream)
                                                                fromViewController.present(view, animated: true)
                                                            })
                                                        }
        }
    }

    private class func loadPresentation(interaction: TSInteraction) -> Presentation? {
        var presentation: Presentation?
        databaseStorage.write { transaction in
            guard let interactionId = interaction.uniqueId else {
                return
            }
            guard let message = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) as? TSMessage else {
                return
            }

            PerMessageExpiration.expireIfNecessary(message: message, transaction: transaction)
            guard !message.perMessageExpirationHasExpired else {
                return
            }

            // Kick off expiration now if necessary.
            if !message.hasPerMessageExpirationStarted {
                PerMessageExpiration.startPerMessageExpiration(forMessage: message, transaction: transaction)
            }

            guard !message.perMessageExpirationHasExpired else {
                return
            }
            guard let attachmentId = message.attachmentIds.firstObject as? String else {
                return
            }
            guard let attachmentStream = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) as? TSAttachmentStream else {
                return
            }
            guard attachmentStream.isValidVisualMedia,
                attachmentStream.isImage || attachmentStream.isAnimated else {
                    return
            }

            presentation = (message: message, attachmentStream: attachmentStream)
        }
        return presentation
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

        let mediaAspectRatio: CGFloat
        let mediaView: UIView
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
        dismissButton.setShadow(opacity: 0.33)

        view.addSubview(progressView)
        progressView.autoSetDimension(.width, toSize: controlSize)
        progressView.autoSetDimension(.height, toSize: controlSize)
        progressView.autoPinEdge(.trailing, to: .trailing, of: mediaView, withOffset: -hMargin)
        progressView.autoPinEdge(.top, to: .top, of: mediaView, withOffset: vMargin)
        progressView.setShadow(opacity: 0.33)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                         action: #selector(rootViewWasTapped)))

        setupDatabaseObservation()

        updateProgress()

        timer = Timer.weakScheduledTimer(withTimeInterval: 0.1, target: self, selector: #selector(progressTimerDidFire), userInfo: nil, repeats: true)
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

    private func updateProgress() {
        AssertIsOnMainThread()

        progressView.progress = currentProgress()
    }

    private func currentProgress() -> CGFloat {
        AssertIsOnMainThread()

        let perMessageExpirationDurationSeconds: UInt32 = message.perMessageExpirationDurationSeconds
        guard perMessageExpirationDurationSeconds > 0 else {
            owsFailDebug("Invalid perMessageExpirationDurationSeconds.")
            return 1
        }
        let perMessageExpireStartedAtMs: UInt64 = message.perMessageExpireStartedAt
        guard perMessageExpireStartedAtMs > 0 else {
            owsFailDebug("Invalid perMessageExpireStartedAt.")
            return 1
        }
        let nowMs: UInt64 = NSDate.ows_millisecondTimeStamp()
        guard nowMs > perMessageExpireStartedAtMs else {
            owsFailDebug("Invalid perMessageExpireStartedAt.")
            return 1
        }
        let elapsedMs: UInt64 = nowMs - perMessageExpireStartedAtMs
        let durationMs: UInt64 = UInt64(perMessageExpirationDurationSeconds) * 1000
        let progress: CGFloat = (CGFloat(elapsedMs) / CGFloat(durationMs)).clamp01()
        return progress
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
            guard let uniqueId = self.message.uniqueId else {
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
    private func progressTimerDidFire() {
        AssertIsOnMainThread()

        updateProgress()
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
