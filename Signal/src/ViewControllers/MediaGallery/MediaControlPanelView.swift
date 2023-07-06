//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol MediaControlPanelDelegate: GalleryRailViewDelegate {
    func mediaControlPanelDidRequestForwardMedia(_ panel: MediaControlPanelView)
    func mediaControlPanelDidRequestShareMedia(_ panel: MediaControlPanelView)
}

// Bottom panel for full-screen media viewer.
// Contains:
// • media "caption" (text of the message that contains currently visible media).
// • thumbnail strip if current media is a part of an "album" (media sent in one message).
// • Share and Forward buttons when in portrait orientation.
// • interactive video player playback bar (hidden for photos).
// • video playback controls (play/pause, rewind, fast forward) (hidden for photos).
class MediaControlPanelView: UIView {

    private let mediaGallery: MediaGallery
    private let spoilerState: SpoilerRenderState
    private weak var delegate: MediaControlPanelDelegate?

    init(mediaGallery: MediaGallery, delegate: MediaControlPanelDelegate, spoilerState: SpoilerRenderState, isLandscapeLayout: Bool) {
        self.mediaGallery = mediaGallery
        self.delegate = delegate
        self.spoilerState = spoilerState
        self.isLandscapeLayout = isLandscapeLayout

        super.init(frame: .zero)

        tintColor = Theme.darkThemePrimaryColor
        preservesSuperviewLayoutMargins = true

        layoutMargins.top = 0

        // Blur Background
        let blurEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        let blurBackgroundView = UIVisualEffectView(effect: blurEffect)
        addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subviews

    private var videoPlaybackProgressView: PlayerProgressView?
    private let videoPlayerProgressViewAreaPortrait = UILayoutGuide()
    private var videoPlayerProgressViewTopMarginPortrait: NSLayoutConstraint?
    private lazy var videoPlayerProgressViewPortraitAreaZeroHeight = videoPlayerProgressViewAreaPortrait.heightAnchor.constraint(equalToConstant: 0)

    private(set) var videoPlaybackControlView: VideoPlaybackControlView?
    private var videoPlaybackUIPortraitConstraints = [NSLayoutConstraint]()
    private var videoPlaybackUILandscapeConstraints = [NSLayoutConstraint]()

    private lazy var captionView = MediaCaptionView(spoilerState: spoilerState)
    private let captionViewArea = UILayoutGuide()
    private lazy var captionViewAreaZeroHeight = captionViewArea.heightAnchor.constraint(equalToConstant: 0)

    private lazy var thumbnailStrip: GalleryRailView = {
        let view = GalleryRailView()
        view.delegate = delegate
        view.itemSize = 40
        view.layoutMargins.top = 0
        view.layoutMargins.bottom = 6
        view.isScrollEnabled = false
        return view
    }()
    private let thumbnailStripArea = UILayoutGuide()
    private var thumbnailStripTopMargin: NSLayoutConstraint?
    private lazy var thumbnailStripAreaZeroHeight = thumbnailStripArea.heightAnchor.constraint(equalToConstant: 0)

    private let buttonsArea = UILayoutGuide()
    private var buttonsAreaTopMargin: NSLayoutConstraint?
    private lazy var buttonsAreaHeight = buttonsArea.heightAnchor.constraint(equalToConstant: 0)

    private lazy var buttonForwardMedia: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Theme.iconImage(.buttonForward), for: .normal)
        button.addTarget(self, action: #selector(didPressForward), for: .touchUpInside)
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.autoPin(toAspectRatio: 1)
        return button
    }()

    private lazy var buttonShareMedia: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Theme.iconImage(.buttonShare), for: .normal)
        button.addTarget(self, action: #selector(didPressShare), for: .touchUpInside)
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(margin: 8)
        button.autoPin(toAspectRatio: 1)
        return button
    }()

    // MARK: Layout

    var isLandscapeLayout: Bool {
        didSet {
            guard oldValue != isLandscapeLayout else { return }
            thumbnailStrip.setIsHidden(shouldHideThumbnailStrip, animated: false)
            setNeedsUpdateConstraints()
        }
    }

    private enum Constants {
        static let buttonAreaHeightPortrait: CGFloat = 44
        static let buttonAreaHeightLandscape: CGFloat = 36
    }

    // Returns true if interface is landscape and current media not a video.
    var shouldBeHidden: Bool {
        guard isLandscapeLayout else { return false }
        if let currentItem {
            return !currentItem.isVideo && captionView.hasNilOrEmptyContent
        }
        return false
    }

    private func setupSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        captionView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailStrip.translatesAutoresizingMaskIntoConstraints = false

        // View Setup
        addSubview(captionView)
        addSubview(thumbnailStrip)
        addSubview(buttonForwardMedia)
        addSubview(buttonShareMedia)

        addLayoutGuide(videoPlayerProgressViewAreaPortrait)
        addLayoutGuide(captionViewArea)
        addLayoutGuide(thumbnailStripArea)
        addLayoutGuide(buttonsArea)

        videoPlayerProgressViewAreaPortrait.identifier = "VideoProgressBarArea"
        captionViewArea.identifier = "CaptionViewArea"
        thumbnailStripArea.identifier = "ThumbnailStripArea"
        buttonsArea.identifier = "ButtonsArea"

        // Setup Layout guides as a vertical stack.
        buttonsAreaTopMargin = buttonsArea.topAnchor.constraint(equalTo: thumbnailStripArea.bottomAnchor)
        addConstraints([
            captionViewArea.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            captionViewArea.topAnchor.constraint(
                equalTo: topAnchor
            ),
            captionViewArea.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),

            videoPlayerProgressViewAreaPortrait.leadingAnchor.constraint(
                equalTo: layoutMarginsGuide.leadingAnchor
            ),
            videoPlayerProgressViewAreaPortrait.topAnchor.constraint(
                equalTo: captionViewArea.bottomAnchor
            ),
            videoPlayerProgressViewAreaPortrait.trailingAnchor.constraint(
                equalTo: layoutMarginsGuide.trailingAnchor
            ),

            thumbnailStripArea.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            thumbnailStripArea.topAnchor.constraint(
                equalTo: videoPlayerProgressViewAreaPortrait.bottomAnchor
            ),
            thumbnailStripArea.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),

            buttonsArea.leadingAnchor.constraint(
                equalTo: layoutMarginsGuide.leadingAnchor
            ),
            buttonsAreaTopMargin!,
            buttonsArea.trailingAnchor.constraint(
                equalTo: layoutMarginsGuide.trailingAnchor
            ),
            buttonsArea.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor
            ),
            buttonsAreaHeight
        ])

        // Attach leading, top and trailing edges of each view to respective layout guide.
        thumbnailStripTopMargin = thumbnailStrip.topAnchor.constraint(equalTo: thumbnailStripArea.topAnchor)
        addConstraints([
            captionView.leadingAnchor.constraint(equalTo: captionViewArea.leadingAnchor),
            captionView.topAnchor.constraint(equalTo: captionViewArea.topAnchor, constant: 12),
            captionView.trailingAnchor.constraint(equalTo: captionViewArea.trailingAnchor),
            {
                let constraint = captionView.bottomAnchor.constraint(equalTo: captionViewArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),

            thumbnailStrip.leadingAnchor.constraint(equalTo: thumbnailStripArea.leadingAnchor),
            thumbnailStripTopMargin!,
            thumbnailStrip.trailingAnchor.constraint(equalTo: thumbnailStripArea.trailingAnchor),
            {
                let constraint = thumbnailStrip.bottomAnchor.constraint(equalTo: thumbnailStripArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }()
       ])

        // Position Share and Forward buttons.
        addConstraints([
            buttonForwardMedia.layoutMarginsGuide.trailingAnchor.constraint(
                equalTo: buttonsArea.trailingAnchor
            ),
            buttonForwardMedia.topAnchor.constraint(equalTo: buttonsArea.topAnchor),
            {
                let constraint = buttonForwardMedia.bottomAnchor.constraint(equalTo: buttonsArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),

            buttonShareMedia.layoutMarginsGuide.leadingAnchor.constraint(
                equalTo: buttonsArea.leadingAnchor
            ),
            buttonShareMedia.topAnchor.constraint(equalTo: buttonsArea.topAnchor),
            {
                let constraint = buttonShareMedia.bottomAnchor.constraint(equalTo: buttonsArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }()
        ])

        // TODO: Add "Read More"
        captionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCaption)))

        setNeedsUpdateConstraints()
    }

    override func updateConstraints() {
        super.updateConstraints()

        let videoPlaybackControlsVisible = videoPlayer != nil

        videoPlayerProgressViewPortraitAreaZeroHeight.isActive = isLandscapeLayout || !videoPlaybackControlsVisible

        videoPlaybackControlView?.isLandscapeLayout = isLandscapeLayout
        videoPlaybackProgressView?.isVerticallyCompactLayout = isLandscapeLayout

        if isLandscapeLayout {
            if videoPlaybackControlsVisible {
                NSLayoutConstraint.deactivate(videoPlaybackUIPortraitConstraints)
                NSLayoutConstraint.activate(videoPlaybackUILandscapeConstraints)
            }
        } else {
            if videoPlaybackControlsVisible {
                NSLayoutConstraint.deactivate(videoPlaybackUILandscapeConstraints)
                NSLayoutConstraint.activate(videoPlaybackUIPortraitConstraints)
            }
        }

        let hasCaption = !captionView.hasNilOrEmptyContent
        captionViewAreaZeroHeight.isActive = !hasCaption

        let hideThumbnailStrip = shouldHideThumbnailStrip
        thumbnailStripAreaZeroHeight.isActive = hideThumbnailStrip
        // If thumbnail strip is visible - update spacing between the strip and UI element above.
        thumbnailStripTopMargin?.constant = {
            if hideThumbnailStrip {
                return 0
            }
            if videoPlaybackControlsVisible {
                return 8
            }
            if hasCaption {
                return 16  // Totals 20 with MediaCaptionView's bottom inset of 4
            }
            return 23
        }()

        // Do not show Forward and Share buttons in landscape orientation (those are displayed in the navbar).
        buttonForwardMedia.isHidden = isLandscapeLayout
        buttonShareMedia.isHidden = isLandscapeLayout

        buttonsAreaTopMargin?.constant = isLandscapeLayout ? 4 : 8
        buttonsAreaHeight.constant = isLandscapeLayout ?
        (videoPlaybackControlsVisible ? Constants.buttonAreaHeightLandscape : 0) : Constants.buttonAreaHeightPortrait
    }

    // MARK: Expandable Caption

    @objc
    private func didTapCaption(_ gestureRecognizer: UITapGestureRecognizer) {
        // Let the view handle first; if it does, exit.
        if captionView.handleTap(gestureRecognizer) {
            return
        }

        guard captionView.canBeExpanded else { return }

        let animator = UIViewPropertyAnimator(duration: 0.25, springDamping: 0.645, springResponse: 0.25)
        animator.addAnimations {
            self.captionView.isExpanded = !self.captionView.isExpanded
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    // MARK: Media Rail

    private static var galleryCellConfiguration = GalleryRailCellConfiguration(
        cornerRadius: 6,
        itemBorderWidth: 0,
        itemBorderColor: nil,
        focusedItemBorderWidth: 2,
        focusedItemBorderColor: .white,
        focusedItemOverlayColor: nil
    )

    // Only show thumbnail strip for albums (>1 media in one message) and in portrait.
    private var shouldHideThumbnailStrip: Bool {
        if isLandscapeLayout { return true }
        guard let currentMediaAlbum else { return true }
        return currentMediaAlbum.items.count < 2
    }

    // MARK: Video Playback Controls

    private func getOrCreateVideoPlaybackControlView() -> VideoPlaybackControlView {
        if let videoPlaybackControlView {
            return videoPlaybackControlView
        }
        let videoPlaybackControlView = VideoPlaybackControlView()
        videoPlaybackControlView.translatesAutoresizingMaskIntoConstraints = false
        videoPlaybackControlView.isLandscapeLayout = isLandscapeLayout
        videoPlaybackControlView.delegate = self
        addSubview(videoPlaybackControlView)

        addConstraints([
            videoPlaybackControlView.centerYAnchor.constraint(equalTo: buttonsArea.centerYAnchor),
            videoPlaybackControlView.heightAnchor.constraint(equalTo: buttonsArea.heightAnchor)
        ])

        videoPlaybackUIPortraitConstraints += [
            videoPlaybackControlView.centerXAnchor.constraint(equalTo: buttonsArea.centerXAnchor)
        ]
        videoPlaybackUILandscapeConstraints += [
            videoPlaybackControlView.leadingAnchor.constraint(equalTo: buttonsArea.leadingAnchor, constant: -8)
        ]

        self.videoPlaybackControlView = videoPlaybackControlView

        return videoPlaybackControlView
    }

    private func getOrCreateVideoPlaybackProgressView() -> PlayerProgressView {
        if let videoPlaybackProgressView {
            return videoPlaybackProgressView
        }

        let videoPlaybackProgressView = PlayerProgressView(forVerticallyCompactLayout: isLandscapeLayout)
        videoPlaybackProgressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoPlaybackProgressView)

        videoPlayerProgressViewTopMarginPortrait = videoPlaybackProgressView.topAnchor.constraint(
            equalTo: videoPlayerProgressViewAreaPortrait.topAnchor
        )
        videoPlaybackUIPortraitConstraints += [
            videoPlaybackProgressView.leadingAnchor.constraint(
                equalTo: videoPlayerProgressViewAreaPortrait.leadingAnchor
            ),
            videoPlayerProgressViewTopMarginPortrait!,
            videoPlaybackProgressView.trailingAnchor.constraint(
                equalTo: videoPlayerProgressViewAreaPortrait.trailingAnchor
            ),
            {
                let constraint = videoPlaybackProgressView.bottomAnchor.constraint(
                    equalTo: videoPlayerProgressViewAreaPortrait.bottomAnchor
                )
                constraint.priority = .defaultHigh + 100
                return constraint
            }()
        ]

        let videoPlaybackControlView = getOrCreateVideoPlaybackControlView()
        videoPlaybackUILandscapeConstraints += [
            videoPlaybackProgressView.leadingAnchor.constraint(equalTo: videoPlaybackControlView.trailingAnchor, constant: 28),
            videoPlaybackProgressView.centerYAnchor.constraint(equalTo: videoPlaybackControlView.centerYAnchor),
            videoPlaybackProgressView.trailingAnchor.constraint(equalTo: buttonsArea.trailingAnchor)
        ]

        self.videoPlaybackProgressView = videoPlaybackProgressView

        return videoPlaybackProgressView
    }

    private func performInitialLayoutForPlayerControls() {
        guard let videoPlaybackControlView, let videoPlaybackProgressView else { return }

        updateConstraints()

        videoPlaybackControlView.setIsHidden(true, animated: false)
        videoPlaybackProgressView.setIsHidden(true, animated: false)

        UIView.performWithoutAnimation {
            videoPlaybackControlView.layoutIfNeeded()
            videoPlaybackProgressView.layoutIfNeeded()

            videoPlaybackControlView.center = buttonsArea.layoutFrame.center
            videoPlaybackProgressView.center = {
                if isLandscapeLayout {
                    return buttonsArea.layoutFrame.center
                } else {
                    return videoPlayerProgressViewAreaPortrait.layoutFrame.center
                }
            }()
        }
    }

    // TODO: smaller buttons in landscape

    // MARK: Media Item

    private var currentItem: MediaGalleryItem?

    private var currentMediaAlbum: MediaGalleryAlbum?

    private var videoPlayer: VideoPlayer?

    // Call when user taps on media rail thumbnail and there's a non-interactive transition to a new media.
    func configureWithMediaItem(_ item: MediaGalleryItem, videoPlayer: VideoPlayer?, animated: Bool) {
        guard currentItem !== item else { return }

        currentItem = item
        if currentMediaAlbum?.items.contains(item) != true {
            currentMediaAlbum = mediaGallery.album(for: item)
        }

        // Show / hide video playback controls.
        if let videoPlayer, item.isVideo {
            self.videoPlayer = videoPlayer
            let playerControlsJustCreated = videoPlaybackControlView == nil

            let playerControlsView = getOrCreateVideoPlaybackControlView()
            playerControlsView.updateWithMediaItem(item)
            playerControlsView.updateStatusWithPlayer(videoPlayer)

            let playerProgressView = getOrCreateVideoPlaybackProgressView()
            playerProgressView.videoPlayer = videoPlayer

            // Set proper initial layout frame for video playback controls so that
            // animations are nice when swiping from photo to a video for the first time during view lifecyclce.
            if playerControlsJustCreated && animated {
                performInitialLayoutForPlayerControls()
            }

            playerControlsView.setIsHidden(false, animated: animated)
            playerProgressView.setIsHidden(false, animated: animated)
        } else {
            self.videoPlayer = nil

            if let videoPlaybackControlView, !videoPlaybackControlView.isHidden {
                videoPlaybackControlView.setIsHidden(true, animated: animated)
            }
            if let videoPlaybackProgressView, !videoPlaybackProgressView.isHidden {
                videoPlaybackProgressView.setIsHidden(true, animated: animated)
                videoPlaybackProgressView.videoPlayer = nil
            }
        }

        // Update caption.
        captionView.content = item.captionForDisplay

        // Update media strip.
        thumbnailStrip.configureCellViews(
            itemProvider: currentMediaAlbum!,
            focusedItem: item,
            cellViewBuilder: { _ in
                return GalleryRailCellView(configuration: Self.galleryCellConfiguration)
            },
            animated: animated && !thumbnailStrip.isHidden
        )
        thumbnailStrip.setIsHidden(shouldHideThumbnailStrip, animated: animated)

        setNeedsUpdateConstraints()
    }

    // MARK: Actions

    @objc
    private func didPressShare(_ sender: Any) {
        delegate?.mediaControlPanelDidRequestShareMedia(self)
    }

    @objc
    private func didPressForward(_ sender: Any) {
        delegate?.mediaControlPanelDidRequestForwardMedia(self)
    }
}

extension MediaControlPanelView: VideoPlaybackStatusObserver {

    func videoPlayerStatusChanged(_ videoPlayer: VideoPlayer) {
        if let videoPlaybackControlView {
            videoPlaybackControlView.updateStatusWithPlayer(videoPlayer)
        }
    }
}

extension MediaControlPanelView: VideoPlaybackControlViewDelegate {

    func videoPlaybackControlViewDidTapPlayPause(_ videoPlaybackControlView: VideoPlaybackControlView) {
        guard let videoPlayer else { return }

        if videoPlayer.isPlaying {
            videoPlayer.pause()
        } else {
            videoPlayer.play()
        }
    }

    func videoPlaybackControlViewDidTapRewind(_ videoPlaybackControlView: VideoPlaybackControlView, duration: TimeInterval) {
        guard let videoPlayer else { return }

        videoPlayer.rewind(duration)
    }

    func videoPlaybackControlViewDidTapFastForward(_ videoPlaybackControlView: VideoPlaybackControlView, duration: TimeInterval) {
        guard let videoPlayer else { return }

        videoPlayer.fastForward(duration)
    }

    func videoPlaybackControlViewDidStartRewind(_ videoPlaybackControlView: VideoPlaybackControlView) {
        guard let videoPlayer else { return }

        videoPlayer.changePlaybackRate(to: -2)
    }

    func videoPlaybackControlViewDidStartFastForward(_ videoPlaybackControlView: VideoPlaybackControlView) {
        guard let videoPlayer else { return }

        videoPlayer.changePlaybackRate(to: 2)
    }

    func videoPlaybackControlViewDidStopRewindOrFastForward(_ videoPlaybackControlView: VideoPlaybackControlView) {
        guard let videoPlayer else { return }

        videoPlayer.restorePlaybackRate()
    }
}
