//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreMedia
import SDWebImage
import SignalServiceKit
import SignalUI

protocol MediaItemViewControllerDelegate: AnyObject {
    func mediaItemViewControllerDidTapMedia(_ viewController: MediaItemViewController)
    func mediaItemViewControllerWillBeginZooming(_ viewController: MediaItemViewController)
    func mediaItemViewControllerFullyZoomedOut(_ viewController: MediaItemViewController)
}

protocol VideoPlaybackStatusProvider: AnyObject {
    var videoPlaybackStatusObserver: VideoPlaybackStatusObserver? { get set }
}

protocol VideoPlaybackStatusObserver: AnyObject {
    func videoPlayerStatusChanged(_ videoPlayer: VideoPlayer)
}

class MediaItemViewController: OWSViewController, VideoPlaybackStatusProvider {

    weak var delegate: MediaItemViewControllerDelegate?

    let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem) {
        self.galleryItem = galleryItem

        super.init()

        image = attachmentStream.thumbnailImageSync(quality: .large)
    }

    deinit {
        stopVideoIfPlaying()
    }

    // MARK: - Layout

    private var scrollView: ZoomableMediaView!

    private(set) var mediaView: UIView!
    private var mediaViewBottomConstraint: NSLayoutConstraint?
    private var mediaViewLeadingConstraint: NSLayoutConstraint?
    private var mediaViewTopConstraint: NSLayoutConstraint?
    private var mediaViewTrailingConstraint: NSLayoutConstraint?

    var videoPlayerView: VideoPlayerView? { mediaView as? VideoPlayerView }
    var videoPlayer: VideoPlayer? { videoPlayerView?.videoPlayer }
    private var buttonPlayVideo: UIButton?

    func zoomOut(animated: Bool) {
        scrollView.zoomOut(animated: animated)
    }

    private func configureVideoPlaybackControls() {
        guard videoPlayerView != nil else {
            owsFailBeta("No videoPlayer")
            return
        }

        var buttonConfiguration: UIButton.Configuration
        if #available(iOS 26, *) {
            buttonConfiguration = .glass()
            buttonConfiguration.baseForegroundColor = .Signal.label
        } else {
            buttonConfiguration = .borderedProminent()
            buttonConfiguration.baseForegroundColor = .black
            buttonConfiguration.baseBackgroundColor = UIColor(white: 1, alpha: 0.75)
        }
        buttonConfiguration.cornerStyle = .capsule
        buttonConfiguration.image = UIImage(named: "play-fill-48")
        buttonConfiguration.contentInsets = .init(margin: 22) // 92 pt button size

        let button = UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.playVideo()
            },
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        self.buttonPlayVideo = button
    }

    // MARK: - Media Views

    private func configureMediaView() {
        buildMediaView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.isUserInteractionEnabled = true
        mediaView.clipsToBounds = true
        mediaView.layer.allowsEdgeAntialiasing = true
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        mediaView.layer.minificationFilter = .trilinear
        mediaView.layer.magnificationFilter = .trilinear

        scrollView = ZoomableMediaView(mediaView: mediaView, onSingleTap: { [weak self] in
            guard let self else { return }
            delegate?.mediaItemViewControllerDidTapMedia(self)
        })
        scrollView.delegate = self
    }

    private func buildMediaView() {
        guard mediaView == nil else { return }

        let view: UIView
        if attachmentStream.contentType.isVideo, galleryItem.renderingFlag == .shouldLoop {
            if attachmentStream.contentType.isVideo, let loopingVideoPlayerView = buildLoopingVideoPlayerView() {
                loopingVideoPlayerView.delegate = self
                view = loopingVideoPlayerView
            } else {
                view = buildPlaceholderView()
            }
        } else if attachmentStream.contentType.isAnimatedImage {
            if let animatedGif = try? attachmentStream.decryptedSDAnimatedImage() {
                view = SDAnimatedImageView(image: animatedGif)
            } else {
                view = buildPlaceholderView()
            }
        } else if image == nil {
            // Still loading thumbnail.
            view = buildPlaceholderView()
        } else if isVideo {
            if attachmentStream.contentType.isVideo, let videoPlayerView = buildVideoPlayerView() {
                videoPlayerView.delegate = self
                videoPlayerView.videoPlayer?.delegate = self

                view = videoPlayerView
            } else {
                view = buildPlaceholderView()
            }
        } else {
            // Present the static image using standard UIImageView
            view = UIImageView(image: image)
        }

        mediaView = view
    }

    private func buildPlaceholderView() -> UIView {
        let view = UIView()
        view.backgroundColor = Theme.washColor
        return view
    }

    private func buildLoopingVideoPlayerView() -> LoopingVideoView? {
        guard let loopingVideo = LoopingVideo(attachmentStream) else {
            owsFailBeta("Invalid looping video")
            return nil
        }
        let videoView = LoopingVideoView()
        videoView.video = loopingVideo
        return videoView
    }

    private func buildVideoPlayerView() -> VideoPlayerView? {
        guard let videoPlayer = try? VideoPlayer(attachment: galleryItem.attachmentStream) else {
            owsFailBeta("Invalid attachment")
            return nil
        }

        videoPlayer.seek(to: .zero)

        let videoPlayerView = VideoPlayerView()
        videoPlayerView.videoPlayer = videoPlayer

        return videoPlayerView
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        configureMediaView()

        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        // Video Playback controls
        if isVideo {
            configureVideoPlaybackControls()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // HACK: Setting the frame to itself *seems* like it should be a no-op, but
        // it ensures the content is drawn at the right frame. In particular I was
        // reproducibly seeing some images squished (they were EXIF rotated, maybe
        // related). similar to this report:
        // https://stackoverflow.com/questions/27961884/swift-uiimageview-stretched-aspect
        view.layoutIfNeeded()
        mediaView.frame = mediaView.frame

        scrollView.updateZoomScaleForLayout()
        scrollView.zoomScale = scrollView.minimumZoomScale
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isVideo, shouldAutoPlayVideo, !hasAutoPlayedVideo {
            playVideo()
            hasAutoPlayedVideo = true
        }

        let timestamp = Date().ows_millisecondsSince1970
        let attachmentId = galleryItem.attachmentStream.attachment.id
        Task {
            try await DependenciesBridge.shared.db.awaitableWrite { tx in
                guard let attachment = DependenciesBridge.shared.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    return
                }
                try DependenciesBridge.shared.attachmentStore.markViewedFullscreen(
                    attachment: attachment,
                    timestamp: timestamp,
                    tx: tx,
                )
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.updateZoomScaleForLayout()
    }

    // MARK: - Helpers

    private var image: UIImage?

    private var attachmentStream: AttachmentStream { galleryItem.attachmentStream.attachmentStream }

    // MARK: - Video Playback

    var shouldAutoPlayVideo: Bool = false

    private var hasAutoPlayedVideo = false

    private var isVideo: Bool {
        galleryItem.isVideo
    }

    private func playVideo() {
        guard let videoPlayerView else {
            owsFailBeta("videoPlayer is nil")
            return
        }

        videoPlayerView.play()
    }

    func stopVideoIfPlaying() {
        if let videoPlayerView {
            videoPlayerView.stop()
        }
    }

    // MARK: - VideoPlaybackStatusProvider

    weak var videoPlaybackStatusObserver: VideoPlaybackStatusObserver?
}

extension MediaItemViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return mediaView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        delegate?.mediaItemViewControllerWillBeginZooming(self)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= scrollView.minimumZoomScale {
            delegate?.mediaItemViewControllerFullyZoomedOut(self)
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        (scrollView as? ZoomableMediaView)?.updateZoomScaleForLayout()
        view.layoutIfNeeded()
    }
}

extension MediaItemViewController: LoopingVideoViewDelegate {
    func loopingVideoViewChangedPlayerItem() {
        scrollView.updateZoomScaleForLayout()
        scrollView.zoomScale = scrollView.minimumZoomScale
    }
}

extension MediaItemViewController: VideoPlayerDelegate {

    func videoPlayerDidPlayToCompletion(_ videoPlayer: VideoPlayer) {
        guard isVideo, let videoPlayerView else { return }

        videoPlayerView.stop()
        buttonPlayVideo?.isHidden = false
    }
}

extension MediaItemViewController: VideoPlayerViewDelegate {

    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView) {
        if let buttonPlayVideo, view.isPlaying {
            buttonPlayVideo.isHidden = true
        }
        if let videoPlaybackStatusObserver, let videoPlayer = view.videoPlayer {
            videoPlaybackStatusObserver.videoPlayerStatusChanged(videoPlayer)
        }
        scrollView.updateZoomScaleForLayout()
    }

    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
    }
}
