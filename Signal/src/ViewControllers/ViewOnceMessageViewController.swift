//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreMedia
import SignalServiceKit
import SignalUI
import YYImage

class ViewOnceMessageViewController: OWSViewController {

    typealias Content = ViewOnceContent

    // MARK: - Properties

    private let content: Content

    // MARK: - Initializers

    init(content: Content) {
        self.content = content

        super.init()
    }

    // MARK: -

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
                                                                fromViewController.presentFullScreen(view, animated: true)
                                                            })
                                                        }
        }
    }

    private class func loadContentForPresentation(interaction: TSInteraction) -> Content? {
        guard let message = interaction as? TSMessage else {
            return nil
        }
        return DependenciesBridge.shared.attachmentViewOnceManager.prepareViewOnceContentForDisplay(message)
    }

    // MARK: - View Lifecycle

    override public func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.ows_black

        let contentView = UIView()
        view.addSubview(contentView)
        contentView.autoPinWidthToSuperview()
        contentView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        contentView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        let defaultMediaView = UIView()
        defaultMediaView.backgroundColor = Theme.darkThemeWashColor
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

        let dismissButton = OWSButton(imageName: Theme.iconName(.buttonX), tintColor: Theme.darkThemePrimaryColor) { [weak self] in
            self?.dismissButtonPressed()
        }
        dismissButton.layer.shadowColor = Theme.darkThemeBackgroundColor.cgColor
        dismissButton.layer.shadowOffset = .zero
        dismissButton.layer.shadowOpacity = 0.7
        dismissButton.layer.shadowRadius = 3.0

        dismissButton.ows_contentEdgeInsets = UIEdgeInsets(top: vMargin, leading: hMargin, bottom: vMargin, trailing: hMargin)
        view.addSubview(dismissButton)
        dismissButton.autoPinEdge(.leading, to: .leading, of: mediaView)
        dismissButton.autoPinEdge(.top, to: .top, of: mediaView)
        dismissButton.setShadow(opacity: 0.66)

        setupDatabaseObservation()
    }

    private func buildMediaView() -> UIView? {
        switch content.type {
        case .loopingVideo:
            guard let asset = try? content.loadAVAsset() else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            let video = LoopingVideo(asset: asset)
            let view = LoopingVideoView()
            view.contentMode = .scaleAspectFit
            view.video = video
            return view
        case .animatedImage:
            guard let image = try? content.loadYYImage() else {
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
        case .stillImage:
            guard let image = try? content.loadImage() else {
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
        case .video:
            let videoContainer = UIView()

            guard let asset = try? content.loadAVAsset() else {
                owsFailDebug("Could not load attachment.")
                return nil
            }
            let player = VideoPlayer(avPlayer: .init(playerItem: .init(asset: asset)), shouldLoop: true)
            self.videoPlayer = player
            player.delegate = self

            let playerView = VideoPlayerView()
            playerView.player = player.avPlayer

            videoContainer.addSubview(playerView)
            playerView.autoPinEdgesToSuperviewEdges()

            let label = UILabel()
            label.textColor = Theme.darkThemePrimaryColor
            label.font = UIFont.dynamicTypeBody.monospaced()
            label.setShadow()

            videoContainer.addSubview(label)
            label.autoPinEdge(toSuperviewMargin: .top, withInset: 16)
            label.autoPinEdge(toSuperviewMargin: .trailing, withInset: 16)

            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .positional
            formatter.allowedUnits = [.minute, .second ]
            formatter.zeroFormattingBehavior = [ .pad ]

            let avPlayer = player.avPlayer
            self.videoPlayerProgressObserver = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 100), queue: nil) { _ in

                guard let item = avPlayer.currentItem else {
                    owsFailDebug("item was unexpectedly nil")
                    label.text = "0:00"
                    return
                }

                let position = avPlayer.currentTime()
                let duration: CMTime = item.asset.duration
                let remainingTime = duration - position
                let remainingSeconds = CMTimeGetSeconds(remainingTime)

                guard let remainingString = formatter.string(from: remainingSeconds) else {
                    owsFailDebug("unable to format time remaining")
                    label.text = "0:00"
                    return
                }

                label.text = remainingString
            }

            return videoContainer
        }
    }

    // MARK: Video

    var videoPlayerProgressObserver: Any?
    var videoPlayer: VideoPlayer?

    func setupDatabaseObservation() {
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.videoPlayer?.play()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Video

    // Once open, this view only dismisses if the message is deleted
    // (e.g. by per-conversation expiration).
    private func dismissIfRemoved() {
        AssertIsOnMainThread()

        let shouldDismiss: Bool = SSKEnvironment.shared.databaseStorageRef.read { transaction in
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
    private func applicationWillEnterForeground() throws {
        AssertIsOnMainThread()

        Logger.debug("")

        dismissIfRemoved()
    }

    @objc
    private func dismissButtonPressed() {
        AssertIsOnMainThread()

        dismiss(animated: true)
    }
}

// MARK: -

extension ViewOnceMessageViewController: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        dismissIfRemoved()
    }

    func databaseChangesDidUpdateExternally() {
        dismissIfRemoved()
    }

    func databaseChangesDidReset() {
        dismissIfRemoved()
    }
}

extension ViewOnceMessageViewController: VideoPlayerDelegate {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: VideoPlayer) {
        // no-op
    }
}
