//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreMedia
import SignalServiceKit
import SignalUI
import YYImage

protocol MediaItemViewControllerDelegate: AnyObject {
    func mediaItemViewControllerDidTapMedia(_ viewController: MediaItemViewController)
    func mediaItemViewController(_ viewController: MediaItemViewController, videoPlaybackStatusDidChange isPlaying: Bool)
}

class MediaItemViewController: OWSViewController {

    weak var delegate: MediaItemViewControllerDelegate?

    let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem, shouldAutoPlayVideo: Bool) {
        self.galleryItem = galleryItem
        self.shouldAutoPlayVideo = shouldAutoPlayVideo

        super.init()

        image = attachmentStream.thumbnailImageLargeSync()
    }

    deinit {
        stopVideoIfPlaying()
    }

    // MARK: - Layout

    private var lastKnownScrollViewWidth: CGFloat = 0
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: view.bounds)
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        return scrollView
    }()

    private(set) var mediaView: UIView!
    private var mediaViewBottomConstraint: NSLayoutConstraint?
    private var mediaViewLeadingConstraint: NSLayoutConstraint?
    private var mediaViewTopConstraint: NSLayoutConstraint?
    private var mediaViewTrailingConstraint: NSLayoutConstraint?

    private var videoPlayer: OWSVideoPlayer?
    private var buttonPlayVideo: UIButton?
    private var videoProgressBar: PlayerProgressBar?

    private func updateZoomScaleAndConstraints() {
        // We want a default layout that...
        //
        // * Has the media visually centered.
        // * The media content should be zoomed to just barely fit by default,
        //   regardless of the content size.
        // * We should be able to safely zoom.
        // * The "min zoom scale" should satisfy the requirements above.
        // * The user should be able to scale in 4x.
        //
        // We use constraint-based layout and adjust
        // UIScrollView.minimumZoomScale, etc.

        // Determine the media's aspect ratio.
        //
        // * mediaView.intrinsicContentSize is most accurate, but
        //   may not be available yet for media that is loaded async.
        // * The self.image.size should always be available if the
        //   media is valid.
        let mediaSize: CGSize
        let mediaIntrinsicSize = mediaView.intrinsicContentSize
        if mediaIntrinsicSize.width > 0 && mediaIntrinsicSize.height > 0 {
            mediaSize = mediaIntrinsicSize
        } else if let imageSize = image?.size, imageSize.width > 0, imageSize.height > 0 {
            mediaSize = imageSize
        } else {
            mediaSize = .zero
        }

        let scrollViewSize = scrollView.bounds.size

        guard mediaSize.isNonEmpty && scrollViewSize.isNonEmpty else {
            // Invalid content or view state.

            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.zoomScale = 1

            mediaViewTopConstraint?.constant = 0
            mediaViewBottomConstraint?.constant = 0
            mediaViewLeadingConstraint?.constant = 0
            mediaViewTrailingConstraint?.constant = 0

            return
        }

        // Center the media view in the scroll view.
        let mediaViewSize = mediaView.frame.size
        let yOffset = max(0, (scrollViewSize.height - mediaViewSize.height) / 2)
        let xOffset = max(0, (scrollViewSize.width - mediaViewSize.width) / 2)
        mediaViewTopConstraint?.constant = yOffset
        mediaViewBottomConstraint?.constant = yOffset
        mediaViewLeadingConstraint?.constant = xOffset
        mediaViewTrailingConstraint?.constant = xOffset

        // Find minScale for .scaleAspectFit-style layout.
        let scaleWidth = scrollViewSize.width / mediaSize.width
        let scaleHeight = scrollViewSize.height / mediaSize.height
        let minScale = min(scaleWidth, scaleHeight)
        let maxScale = minScale * 8

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale

        if scrollView.zoomScale < minScale {
            scrollView.zoomScale = minScale
        } else if scrollView.zoomScale > maxScale {
            scrollView.zoomScale = maxScale
        }
    }

    func zoomOut(animated: Bool) {
        guard scrollView.zoomScale != scrollView.minimumZoomScale else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
    }

    func setShouldHideToolbars(_ hide: Bool) {
        videoProgressBar?.isHidden = hide
    }

    private func configureVideoPlaybackControls() {
        guard let videoPlayer else {
            owsFailBeta("No videoPlayer")
            return
        }

        let videoProgressBar = PlayerProgressBar()
        videoProgressBar.delegate = self
        videoProgressBar.player = videoPlayer.avPlayer
        // Progress bar stays hidden until either:
        // 1. Video completes playing
        // 2. User taps the screen
        videoProgressBar.isHidden = true
        view.addSubview(videoProgressBar)
        videoProgressBar.autoPinWidthToSuperview()
        let videoProgressBarHeight: CGFloat = 44
        videoProgressBar.autoPin(toTopLayoutGuideOf: self, withInset: videoProgressBarHeight)
        videoProgressBar.autoSetDimension(.height, toSize: videoProgressBarHeight)
        self.videoProgressBar = videoProgressBar

        let buttonPlayVideo = OWSButton { [weak self] in
            self?.playVideo()
        }
        view.addSubview(buttonPlayVideo)
        buttonPlayVideo.autoSetDimensions(to: .square(ScaleFromIPhone5(70)))
        buttonPlayVideo.autoCenterInSuperview()
        self.buttonPlayVideo = buttonPlayVideo

        let playVideoCircleView = OWSLayerView.circleView()
        playVideoCircleView.isUserInteractionEnabled = false
        playVideoCircleView.backgroundColor = UIColor(white: 1, alpha: 0.75)
        buttonPlayVideo.addSubview(playVideoCircleView)
        playVideoCircleView.autoPinEdgesToSuperviewEdges()

        let playVideoIconView = UIImageView.withTemplateImageName("play-solid-32", tintColor: .black)
        playVideoIconView.isUserInteractionEnabled = false
        buttonPlayVideo.addSubview(playVideoIconView)
        playVideoIconView.autoSetDimensions(to: .square(ScaleFromIPhone5(30)))
        playVideoIconView.autoCenterInSuperview()
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

        scrollView.addSubview(mediaView)
        mediaViewLeadingConstraint = mediaView.autoPinEdge(toSuperviewEdge: .leading)
        mediaViewTopConstraint = mediaView.autoPinEdge(toSuperviewEdge: .top)
        mediaViewTrailingConstraint = mediaView.autoPinEdge(toSuperviewEdge: .trailing)
        mediaViewBottomConstraint = mediaView.autoPinEdge(toSuperviewEdge: .bottom)

        // We add these gestures to mediaView rather than
        // the root view so that interacting with the video player
        // progress bar doesn't trigger any of these gestures.
        addTapGestureRecognizers(to: mediaView)
    }

    private func buildMediaView() {
        let view: UIView
        if attachmentStream.isLoopingVideo {
            if attachmentStream.isValidVideo, let loopingVideoPlayerView = buildLoopingVideoPlayerView() {
                loopingVideoPlayerView.delegate = self
                view = loopingVideoPlayerView
            } else {
                view = buildPlaceholderView()
            }
        } else if attachmentStream.shouldBeRenderedByYY {
            if attachmentStream.isValidImage, let filePath = attachmentStream.originalFilePath {
                let animatedGif = YYImage(contentsOfFile: filePath)
                view = YYAnimatedImageView(image: animatedGif)
            } else {
                view = buildPlaceholderView()
            }
        } else if image == nil {
            // Still loading thumbnail.
            view = buildPlaceholderView()
        } else if isVideo {
            if attachmentStream.isValidVideo, let (videoPlayer, videoPlayerView) = buildVideoPlayerView() {
                videoPlayer.delegate = self
                videoPlayerView.delegate = self

                self.videoPlayer = videoPlayer

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
        guard let attachmentUrl = attachmentStream.originalMediaURL else {
            owsFailBeta("Invalid URL")
            return nil
        }
        guard let loopingVideo = LoopingVideo(url: attachmentUrl) else {
            owsFailBeta("Invalid looping video")
            return nil
        }
        let videoView = LoopingVideoView()
        videoView.video = loopingVideo
        return videoView
    }

    private func buildVideoPlayerView() -> (OWSVideoPlayer, VideoPlayerView)? {
        guard let attachmentUrl = attachmentStream.originalMediaURL else {
            owsFailBeta("Invalid URL")
            return nil
        }
        if !FileManager.default.fileExists(atPath: attachmentUrl.path) {
            owsFailBeta("Missing video file")
        }

        let videoPlayer = OWSVideoPlayer(url: attachmentUrl)
        videoPlayer.seek(to: .zero)

        let videoPlayerView = VideoPlayerView()
        videoPlayerView.player = videoPlayer.avPlayer

        return (videoPlayer, videoPlayerView)
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        configureMediaView()

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

        updateZoomScaleAndConstraints()
        scrollView.zoomScale = scrollView.minimumZoomScale
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isVideo && shouldAutoPlayVideo && !hasAutoPlayedVideo {
            playVideo()
            hasAutoPlayedVideo = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateZoomScaleAndConstraints()

        // In iOS multi-tasking, the size of root view (and hence the scroll view)
        // is set later, after viewWillAppear, etc.  Therefore we need to reset the
        // zoomScale to the default whenever the scrollView width changes.
        let tolerance: CGFloat = 0.001
        let currentScrollViewWidth = scrollView.frame.width
        if abs(lastKnownScrollViewWidth - currentScrollViewWidth) > tolerance {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
        lastKnownScrollViewWidth = currentScrollViewWidth
    }

    // MARK: - Helpers

    private var image: UIImage?

    private var attachmentStream: TSAttachmentStream { galleryItem.attachmentStream }

    // MARK: - Video Playback

    private let shouldAutoPlayVideo: Bool

    private var hasAutoPlayedVideo = false

    private var isVideo: Bool { attachmentStream.isVideo && !attachmentStream.isLoopingVideo }

    func playVideo() {
        guard let videoPlayer else {
            owsFailBeta("videoPlayer is nil")
            return
        }

        videoPlayer.play()
        buttonPlayVideo?.isHidden = true

        delegate?.mediaItemViewController(self, videoPlaybackStatusDidChange: true)
    }

    func pauseVideo() {
        owsAssertDebug(isVideo)
        guard let videoPlayer else {
            owsFailBeta("videoPlayer is nil")
            return
        }

        videoPlayer.pause()

        delegate?.mediaItemViewController(self, videoPlaybackStatusDidChange: false)
    }

    private func stopVideo() {
        owsAssertDebug(isVideo)
        guard let videoPlayer else {
            owsFailBeta("videoPlayer is nil")
            return
        }

        videoPlayer.stop()
        buttonPlayVideo?.isHidden = false

        delegate?.mediaItemViewController(self, videoPlaybackStatusDidChange: false)
    }

    func stopVideoIfPlaying() {
        if isVideo { stopVideo() }
    }

    // MARK: - Tap Gestures

    private func addTapGestureRecognizers(to view: UIView) {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    @objc
    private func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        delegate?.mediaItemViewControllerDidTapMedia(self)
    }

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        Logger.verbose("Double tap on media")
        guard scrollView.zoomScale == scrollView.minimumZoomScale else {
            // If already zoomed in at all, zoom out all the way.
            zoomOut(animated: true)
            return
        }

        let doubleTapZoomScale: CGFloat = 2

        let zoomWidth = scrollView.width / doubleTapZoomScale
        let zoomHeight = scrollView.height / doubleTapZoomScale

        // center zoom rect around tapLocation
        let tapLocation = gestureRecognizer.location(in: scrollView)
        let zoomX = max(0, tapLocation.x - zoomWidth / 2)
        let zoomY = max(0, tapLocation.y - zoomHeight / 2)
        let zoomRect = CGRect(x: zoomX, y: zoomY, width: zoomWidth, height: zoomHeight)

        let translatedRect = mediaView.convert(zoomRect, from: scrollView)
        scrollView.zoom(to: translatedRect, animated: true)
    }
}

extension MediaItemViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return mediaView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomScaleAndConstraints()
        view.layoutIfNeeded()
    }
}

extension MediaItemViewController: LoopingVideoViewDelegate {
    func loopingVideoViewChangedPlayerItem() {
        updateZoomScaleAndConstraints()
        scrollView.zoomScale = scrollView.minimumZoomScale
    }
}

extension MediaItemViewController: OWSVideoPlayerDelegate {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: OWSVideoPlayer) {
        owsAssertDebug(isVideo)
        owsAssertDebug(self.videoPlayer != nil)
        Logger.verbose("")
        stopVideo()
    }
}

extension MediaItemViewController: VideoPlayerViewDelegate {
    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView) {
        updateZoomScaleAndConstraints()
    }

    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
    }
}

extension MediaItemViewController: PlayerProgressBarDelegate {
    func playerProgressBarDidStartScrubbing(_ playerProgressBar: PlayerProgressBar) {
        guard let videoPlayer else {
            owsFailBeta("No video player.")
            return
        }
        videoPlayer.pause()
    }

    func playerProgressBar(_ playerProgressBar: PlayerProgressBar, scrubbedToTime time: CMTime) {
        guard let videoPlayer else {
            owsFailBeta("No video player.")
            return
        }
        videoPlayer.seek(to: time)
    }

    func playerProgressBar(_ playerProgressBar: PlayerProgressBar, didFinishScrubbingAtTime time: CMTime, shouldResumePlayback: Bool) {
        guard let videoPlayer else {
            owsFailBeta("No video player.")
            return
        }
        videoPlayer.seek(to: time)
        if shouldResumePlayback {
            videoPlayer.play()
        }
    }
}
