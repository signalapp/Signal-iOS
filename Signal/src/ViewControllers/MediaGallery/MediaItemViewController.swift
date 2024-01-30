//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreMedia
import SignalMessaging
import SignalServiceKit
import SignalUI
import YYImage

protocol MediaItemViewControllerDelegate: AnyObject {

    func mediaItemViewControllerDidTapMedia(_ viewController: MediaItemViewController)
    func mediaItemViewControllerWillBeginZooming(_ viewController: MediaItemViewController)
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

        image = attachmentStream.thumbnailImageLargeSync()
    }

    deinit {
        stopVideoIfPlaying()
    }

    // MARK: - Layout

    private var lastKnownScrollViewSafeAreaSize: CGSize = .zero
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

    var videoPlayerView: VideoPlayerView? { mediaView as? VideoPlayerView }
    var videoPlayer: VideoPlayer? { videoPlayerView?.videoPlayer }
    private var buttonPlayVideo: UIButton?

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

        let scrollViewSize = scrollView.safeAreaLayoutGuide.layoutFrame.size

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
        let yOffset = max(0, (scrollView.bounds.height - mediaViewSize.height) / 2)
        let xOffset = max(0, (scrollView.bounds.width - mediaViewSize.width) / 2)
        mediaViewTopConstraint?.constant = yOffset
        mediaViewBottomConstraint?.constant = yOffset
        mediaViewLeadingConstraint?.constant = xOffset
        mediaViewTrailingConstraint?.constant = -xOffset

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

    private func resetScrollViewZoomIfNecessary() {
        // In iOS multi-tasking, the size of root view (and hence the scroll view)
        // is set later, after viewWillAppear, etc.  Therefore we need to reset the
        // zoomScale to the default whenever the scrollView width changes.
        let currentScrollViewSize = scrollView.safeAreaLayoutGuide.layoutFrame.size
        if !(currentScrollViewSize - lastKnownScrollViewSafeAreaSize).asPoint.fuzzyEquals(.zero, tolerance: 0.001) {
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
        lastKnownScrollViewSafeAreaSize = currentScrollViewSize
    }

    func zoomOut(animated: Bool) {
        guard scrollView.zoomScale != scrollView.minimumZoomScale else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
    }

    private func configureVideoPlaybackControls() {
        guard videoPlayerView != nil else {
            owsFailBeta("No videoPlayer")
            return
        }

        let buttonPlayVideo = OWSButton { [weak self] in
            self?.playVideo()
        }
        view.addSubview(buttonPlayVideo)
        buttonPlayVideo.autoSetDimensions(to: .square(.scaleFromIPhone5(70)))
        buttonPlayVideo.autoCenterInSuperview()
        self.buttonPlayVideo = buttonPlayVideo

        let playVideoCircleView = OWSLayerView.circleView()
        playVideoCircleView.isUserInteractionEnabled = false
        playVideoCircleView.backgroundColor = UIColor(white: 1, alpha: 0.75)
        buttonPlayVideo.addSubview(playVideoCircleView)
        playVideoCircleView.autoPinEdgesToSuperviewEdges()

        let playVideoIconView = UIImageView.withTemplateImageName("play-fill-32", tintColor: .black)
        playVideoIconView.isUserInteractionEnabled = false
        buttonPlayVideo.addSubview(playVideoIconView)
        playVideoIconView.autoSetDimensions(to: .square(.scaleFromIPhone5(30)))
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
        guard mediaView == nil else { return }

        let view: UIView
        if attachmentStream.isLoopingVideo {
            if attachmentStream.isValidVideo, let loopingVideoPlayerView = buildLoopingVideoPlayerView() {
                loopingVideoPlayerView.delegate = self
                view = loopingVideoPlayerView
            } else {
                view = buildPlaceholderView()
            }
        } else if attachmentStream.isAnimatedContent {
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
            if attachmentStream.isValidVideo, let videoPlayerView = buildVideoPlayerView() {
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

    private func buildVideoPlayerView() -> VideoPlayerView? {
        guard let attachmentUrl = attachmentStream.originalMediaURL else {
            owsFailBeta("Invalid URL")
            return nil
        }
        if !FileManager.default.fileExists(atPath: attachmentUrl.path) {
            owsFailBeta("Missing video file")
        }

        let videoPlayer = VideoPlayer(url: attachmentUrl)
        videoPlayer.seek(to: .zero)

        let videoPlayerView = VideoPlayerView()
        videoPlayerView.videoPlayer = videoPlayer

        return videoPlayerView
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
        resetScrollViewZoomIfNecessary()
   }

    // MARK: - Helpers

    private var image: UIImage?

    private var attachmentStream: TSAttachmentStream { galleryItem.attachmentStream }

    // MARK: - Video Playback

    var shouldAutoPlayVideo: Bool = false

    private var hasAutoPlayedVideo = false

    private var isVideo: Bool { attachmentStream.isVideoMimeType && !attachmentStream.isLoopingVideo }

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
        updateZoomScaleAndConstraints()
    }

    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
    }
}
