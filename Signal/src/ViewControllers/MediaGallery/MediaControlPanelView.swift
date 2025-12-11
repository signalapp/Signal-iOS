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

/// Bottom panel for full-screen media viewer.
/// Contains:
/// • media "caption" (text of the message that contains currently visible media).
/// • thumbnail strip if current media is a part of an "album" (media sent in one message).
/// • Share and Forward buttons when in portrait orientation.
/// • interactive video player playback bar (hidden for photos).
/// • video playback controls (play/pause, rewind, fast forward) (hidden for photos).
class MediaControlPanelView: UIView {

    private let mediaGallery: MediaGallery
    private let spoilerState: SpoilerRenderState
    private weak var delegate: MediaControlPanelDelegate?

    // Add all content here.
    private var contentView: UIView!

    init(
        mediaGallery: MediaGallery,
        delegate: MediaControlPanelDelegate,
        spoilerState: SpoilerRenderState
    ) {
        self.mediaGallery = mediaGallery
        self.delegate = delegate
        self.spoilerState = spoilerState

        super.init(frame: .zero)

        tintColor = .Signal.label
        directionalLayoutMargins = .zero
        preservesSuperviewLayoutMargins = true
        isVerticallyCompactLayout = traitCollection.verticalSizeClass == .compact

        // iOS 26: Glass Container
        // Pre-iOS 26: Blur Background
        let visualEffect: UIVisualEffect = if #available(iOS 26, *) { UIGlassContainerEffect() } else { UIBlurEffect(style: .systemChromeMaterial) }
        let visualEffectView = UIVisualEffectView(effect: visualEffect)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentView = visualEffectView.contentView

        setupSubviews()

        // New APIs for tracking trait changes.
        if #available(iOS 17, *) {
            registerForTraitChanges([ UITraitVerticalSizeClass.self ]) { (self: Self, previousTraitCollection) in
                self.isVerticallyCompactLayout = self.traitCollection.verticalSizeClass == .compact
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subviews

    private struct ContentLayoutGuideEdgeConstraints {
        let top: NSLayoutConstraint
        let leading: NSLayoutConstraint
        let trailing: NSLayoutConstraint
        let bottom: NSLayoutConstraint
    }

    // This will be used to define area for entire contents.
    // Other layout guides will be constrained relative to this one.
    private let contentLayoutGuide = UILayoutGuide()
    // Adjustable and therefore non-nil on iOS 26.
    private var contentLayoutGuideEdgeConstraints: ContentLayoutGuideEdgeConstraints?
    // On iOS 26 bottom content margin is fixed on all devices in all orientations.
    private static let contentLayoutGuideBottomMargin: CGFloat = 28

    // Glass background for when caption view and video progress bar are joined in one glass panel.
    // Both controls also have their own glass backgrounds that can be disabled.
    // It is developer's responsibility to enable either shared glass background
    // or individual glass backgrounds.
    private var captionAndMediaControlsGlassBackgroundView: UIVisualEffectView?

    // Top most area.
    private let captionViewArea = UILayoutGuide()
    private lazy var captionView = MediaCaptionView(spoilerState: spoilerState)

    // Second from the top area.
    private let videoPlayerControlsArea = UILayoutGuide()
    private(set) var videoPlaybackControlView: VideoPlaybackControlView?
    private var videoPlaybackProgressView: PlayerProgressView?
    private var videoPlayerControlsConstraintsPortrait = [NSLayoutConstraint]()
    private var videoPlayerControlsConstraintsLandscape = [NSLayoutConstraint]()

    // Third from the top area.
    private let thumbnailStripArea = UILayoutGuide()
    private lazy var thumbnailStrip: GalleryRailView = {
        let view = GalleryRailView()
        view.delegate = delegate
        view.itemSize = 40
        view.layoutMargins.top = 0
        view.layoutMargins.bottom = 6
        view.isScrollEnabled = false
        return view
    }()

    // Bottom area.
    // Not visible in landscape (`compact` vertical size class).
    private let buttonArea = UILayoutGuide()
    private var buttonAreaLeadingEdgeConstraint: NSLayoutConstraint?
    private var buttonAreaTrailingEdgeConstraint: NSLayoutConstraint?

    // These allow to shrink areas to a zero height making them not visible.
    private lazy var captionViewAreaZeroHeightConstraint = captionViewArea.heightAnchor.constraint(equalToConstant: 0)
    private lazy var videoPlayerControlsAreaZeroHeightConstraint =
        videoPlayerControlsArea.heightAnchor.constraint(equalToConstant: 0)
    private lazy var thumbnailStripAreaZeroHeightConstraint = thumbnailStripArea.heightAnchor.constraint(equalToConstant: 0)
    private lazy var buttonAreaZeroHeightConstraint = buttonArea.heightAnchor.constraint(equalToConstant: 0)

    // These control vertical spacing between UI elements (their layout guides).
    private var captionViewAreaBottomToVideoPlayerControlsAreaTop: NSLayoutConstraint?
    private var videoPlayerControlsAreaBottomToThumbnailStripTop: NSLayoutConstraint?
    private var thumbnailStripAreaBottomToButtonsAreaTop: NSLayoutConstraint?

    // This controls how large the bottom button is. Insets are added to 24x24 button icons.
    private static let buttonContentInset: CGFloat = if #available(iOS 26, *) { 10 } else { 8 }
    private lazy var buttonForwardMedia: UIButton = {
        let configuration: UIButton.Configuration = if #available(iOS 26, *) { .glass() } else { .plain() }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.didPressForward()
        })
        button.configuration?.image = Theme.iconImage(.buttonForward)
        button.configuration?.contentInsets = .init(margin: Self.buttonContentInset)
        return button
    }()

    private lazy var buttonShareMedia: UIButton = {
        let configuration: UIButton.Configuration = if #available(iOS 26, *) { .glass() } else { .plain() }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.didPressShare()
        })
        button.configuration?.image = Theme.iconImage(.buttonShare)
        button.configuration?.contentInsets = .init(margin: Self.buttonContentInset)
        return button
    }()

    // Convenience method to create a "regular" glass effect that is interactive.
    @available(iOS 26, *)
    private func interactiveGlassEffect() -> UIVisualEffect? {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        return glassEffect
    }

    // MARK: Layout

    private(set) var isVerticallyCompactLayout: Bool = false {
        didSet {
            guard oldValue != isVerticallyCompactLayout else { return }

            updateCaptionAndVideoControls()
            updateThumbnailStripLayout()
            updateBottomButtonsLayout()

            setNeedsUpdateConstraints()
        }
    }

    // Returns true if interface is landscape and current media is not a video or there's a caption.
    var shouldBeHidden: Bool {
        guard isVerticallyCompactLayout else { return false }
        if let currentItem, currentItem.isVideo {
            return false
        }
        if captionView.isEmpty == false {
            return false
        }
        // On iOS 26 we do show thumbnail strip in landscape because bottom panel doesn't have a background.
        if #available(iOS 26, *) {
            return showThumbnailStrip == false
        }
        return true
    }

    private func setupSubviews() {
        //
        // I. Setup layout guides.
        //
        contentLayoutGuide.identifier = "ContentArea"
        captionViewArea.identifier = "CaptionViewArea"
        videoPlayerControlsArea.identifier = "VideoPlayerControlsArea"
        thumbnailStripArea.identifier = "ThumbnailStripArea"
        buttonArea.identifier = "ButtonArea"

        addLayoutGuide(contentLayoutGuide)
        addLayoutGuide(captionViewArea)
        addLayoutGuide(videoPlayerControlsArea)
        addLayoutGuide(thumbnailStripArea)
        addLayoutGuide(buttonArea)

        //
        // i. Content layout guide.
        //
        let topEdgeConstraint, leadingEdgeConstraint, trailingEdgeConstraint, bottomEdgeConstraint: NSLayoutConstraint

        if #available(iOS 26, *) {
            // Top edge is always at the view's top edge.
            topEdgeConstraint = contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor)

            // iOS 26 landscape (non-zero left and right safe area insets): aligned with outside edges of navigation bar
            // buttons (fixed 38 pts margin).
            // iOS 26 portrait, landscape on older phones: aligned to view's leading and trailing margins.
            leadingEdgeConstraint = contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor)
            trailingEdgeConstraint = contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor)

            // Fixed distance to bottom edge on all devices in all orientations.
            bottomEdgeConstraint = contentLayoutGuide.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Self.contentLayoutGuideBottomMargin
            )
        } else {
            // Top edge is always at the view's top edge with a default padding.
            topEdgeConstraint = contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: 8)

            // Pre-iOS 26: aligned to view's leading and trailing margins.
            leadingEdgeConstraint = contentLayoutGuide.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)
            trailingEdgeConstraint = contentLayoutGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
            // Bottom buttons have padding baked in and therefore can rest against view's bottom edge
            // if there's no bottom safe area inset (home button devices, landscape layout).
            bottomEdgeConstraint = contentLayoutGuide.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        }

        NSLayoutConstraint.activate([
            topEdgeConstraint,
            leadingEdgeConstraint,
            trailingEdgeConstraint,
            bottomEdgeConstraint
        ])

        // Keep reference to constraints and update them as necessary (see `updateConstraints`).
        if #available(iOS 26, *) {
            contentLayoutGuideEdgeConstraints = .init(
                top: topEdgeConstraint,
                leading: leadingEdgeConstraint,
                trailing: trailingEdgeConstraint,
                bottom: bottomEdgeConstraint
            )
            updateContentLayoutGuideEdgeConstraints()
        }

        //
        // ii. Setup Layout guides as a vertical stack within `contentLayoutGuide`.
        //
        let buttonAreaLeadingEdgeConstraint = buttonArea.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor)
        let buttonAreaTrailingEdgeConstraint = buttonArea.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor)
        if #available(iOS 26, *) {
            // Remember those with the purpose of updating as necessary in `updateConstraints`.
            // We do this because bottom buttons by design might need to be moved further away from screen edges.
            self.buttonAreaLeadingEdgeConstraint = buttonAreaLeadingEdgeConstraint
            self.buttonAreaTrailingEdgeConstraint = buttonAreaTrailingEdgeConstraint

            updateButtonAreaEdgeConstraints()
        } else {
            // Actual buttons are a little bit larger than their images.
            // Offset leading and trailing edges by the same amount
            // to make visible button shapes to be aligned with view's layout margins.
            buttonAreaLeadingEdgeConstraint.constant = -Self.buttonContentInset
            buttonAreaTrailingEdgeConstraint.constant = Self.buttonContentInset
        }

        // Vertical spacers between layout guides.
        // All are initialized with `0` constant value that matches initial layout.
        captionViewAreaBottomToVideoPlayerControlsAreaTop = videoPlayerControlsArea.topAnchor.constraint(
            equalTo: captionViewArea.bottomAnchor,
        )
        videoPlayerControlsAreaBottomToThumbnailStripTop = thumbnailStripArea.topAnchor.constraint(
            equalTo: videoPlayerControlsArea.bottomAnchor
        )
        thumbnailStripAreaBottomToButtonsAreaTop = buttonArea.topAnchor.constraint(
            equalTo: thumbnailStripArea.bottomAnchor
        )

        NSLayoutConstraint.activate([
            // a. Horizontal.
            captionViewArea.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            captionViewArea.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),

            videoPlayerControlsArea.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            videoPlayerControlsArea.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),

            // This control is horizontally scrollable and therefore goes edge-to-edge.
            thumbnailStripArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailStripArea.trailingAnchor.constraint(equalTo: trailingAnchor),

            buttonAreaLeadingEdgeConstraint,
            buttonAreaTrailingEdgeConstraint,

            // b. Vertical
            captionViewArea.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            captionViewAreaBottomToVideoPlayerControlsAreaTop!,
            videoPlayerControlsAreaBottomToThumbnailStripTop!,
            thumbnailStripAreaBottomToButtonsAreaTop!,
            buttonArea.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),

            // Initialize all areas with zero height constraint active - matches initial state.
            captionViewAreaZeroHeightConstraint,
            videoPlayerControlsAreaZeroHeightConstraint,
            thumbnailStripAreaZeroHeightConstraint,
        ])

        // Setup views.
        captionView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailStrip.translatesAutoresizingMaskIntoConstraints = false
        buttonForwardMedia.translatesAutoresizingMaskIntoConstraints = false
        buttonShareMedia.translatesAutoresizingMaskIntoConstraints = false

        // These are hidden initially.
        // Video player controls are created on demand.
        captionView.isHidden = true
        thumbnailStrip.isHidden = true

        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: nil)
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.clipsToBounds = true
            glassEffectView.cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: 26))
            contentView.addSubview(glassEffectView)
            NSLayoutConstraint.activate([
                glassEffectView.topAnchor.constraint(equalTo: captionViewArea.topAnchor),
                glassEffectView.leadingAnchor.constraint(equalTo: captionViewArea.leadingAnchor),
                glassEffectView.trailingAnchor.constraint(equalTo: captionViewArea.trailingAnchor),
                glassEffectView.bottomAnchor.constraint(equalTo: videoPlayerControlsArea.bottomAnchor),
            ])

            glassEffectView.contentView.addSubview(captionView)

            captionAndMediaControlsGlassBackgroundView = glassEffectView
        } else {
            contentView.addSubview(captionView)
        }

        contentView.addSubview(thumbnailStrip)
        contentView.addSubview(buttonForwardMedia)
        contentView.addSubview(buttonShareMedia)

        // Constraints with non-required priority allow us to shrink height of the corresponding layout guide
        // to zero while keeping height of the UI elements intact. Combined with setting element's alpha to `0` or `1`
        // we get nice animations when switching between media items.
        NSLayoutConstraint.activate([
            captionView.leadingAnchor.constraint(equalTo: captionViewArea.leadingAnchor),
            captionView.topAnchor.constraint(equalTo: captionViewArea.topAnchor),
            captionView.trailingAnchor.constraint(equalTo: captionViewArea.trailingAnchor),
            {
                let constraint = captionView.bottomAnchor.constraint(equalTo: captionViewArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),

            {
                let constraint = thumbnailStrip.topAnchor.constraint(equalTo: thumbnailStripArea.topAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),
            thumbnailStrip.leadingAnchor.constraint(equalTo: thumbnailStripArea.leadingAnchor),
            thumbnailStrip.trailingAnchor.constraint(equalTo: thumbnailStripArea.trailingAnchor),
            thumbnailStrip.bottomAnchor.constraint(equalTo: thumbnailStripArea.bottomAnchor),

            buttonShareMedia.topAnchor.constraint(equalTo: buttonArea.topAnchor),
            buttonShareMedia.widthAnchor.constraint(equalTo: buttonShareMedia.heightAnchor),
            buttonShareMedia.leadingAnchor.constraint(equalTo: buttonArea.leadingAnchor),
            {
                let constraint = buttonShareMedia.bottomAnchor.constraint(equalTo: buttonArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),

            buttonForwardMedia.topAnchor.constraint(equalTo: buttonArea.topAnchor),
            buttonForwardMedia.widthAnchor.constraint(equalTo: buttonForwardMedia.heightAnchor),
            buttonForwardMedia.trailingAnchor.constraint(equalTo: buttonArea.trailingAnchor),
            {
                let constraint = buttonForwardMedia.bottomAnchor.constraint(equalTo: buttonArea.bottomAnchor)
                constraint.priority = .defaultHigh + 100
                return constraint
            }(),
        ])

        // TODO: Add "Read More"
        captionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCaption)))

        updateBottomButtonsLayout()
    }

    override func updateConstraints() {
        super.updateConstraints()

        // Video playback controls.
        let showVideoPlaybackControls = (videoPlayer != nil)
        if showVideoPlaybackControls {
            if isVerticallyCompactLayout {
                NSLayoutConstraint.deactivate(videoPlayerControlsConstraintsPortrait)
                NSLayoutConstraint.activate(videoPlayerControlsConstraintsLandscape)
            } else {
                NSLayoutConstraint.deactivate(videoPlayerControlsConstraintsLandscape)
                NSLayoutConstraint.activate(videoPlayerControlsConstraintsPortrait)
            }
        }

        if #available(iOS 26, *) {
            updateContentLayoutGuideEdgeConstraints()
            updateButtonAreaEdgeConstraints()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Trait collection change tracking on iOS 17+ is set up in `init()` using newer APIs.
        if #unavailable(iOS 17), previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass {
            isVerticallyCompactLayout = traitCollection.verticalSizeClass == .compact
        }
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        // On iOS 26 the layout is more flexible and depends on view's layout margins.
        if #available(iOS 26, *) {
            setNeedsUpdateConstraints()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()

        // On iOS 26 the layout is more flexible and depends on view's safe area insets.
        if #available(iOS 26, *) {
            setNeedsUpdateConstraints()
        }
    }

    @available(iOS 26, *)
    private func updateContentLayoutGuideEdgeConstraints() {
        guard let contentLayoutGuideEdgeConstraints else { return }

        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact
        let horizontalInset: CGFloat = 38

        // For leading and trailing edges we have custom margins in landscape on modern iPhones (non-home button).
        // Those margins are designed to align content with navigation bar buttons.
        if isLandscapeLayout, safeAreaInsets.leading > 0 {
            contentLayoutGuideEdgeConstraints.leading.constant = horizontalInset
        } else {
            contentLayoutGuideEdgeConstraints.leading.constant = directionalLayoutMargins.leading
        }
        if isLandscapeLayout, safeAreaInsets.trailing > 0 {
            contentLayoutGuideEdgeConstraints.trailing.constant = -horizontalInset
        } else {
            contentLayoutGuideEdgeConstraints.trailing.constant = -directionalLayoutMargins.trailing
        }
    }

    @available(iOS 26, *)
    private func updateButtonAreaEdgeConstraints() {
        guard let buttonAreaLeadingEdgeConstraint, let buttonAreaTrailingEdgeConstraint else { return }

        var leadingInset: CGFloat = 0
        var trailingInset: CGFloat = 0
        // In portrait, shrink the button area, making its leading and trailing insets
        // equal to the bottom content layout guide inset.
        // The purpose is the place Share and Forward buttons squarely in their respective corners of the screen.
        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact
        if !isLandscapeLayout {
            // To calculate inset relative to `contentLayoutGuide`'s leading and trailing anchors
            // we rely on the fact that they are constrained without offset to view's leading and trailing anchors.
            // More correct approach would have been to use `contentLayoutGuide.layoutFrame` but that one
            // might not yet be at it's final dimensions at this point.
            let screenEdgeInset = Self.contentLayoutGuideBottomMargin
            leadingInset = screenEdgeInset - directionalLayoutMargins.leading
            trailingInset = screenEdgeInset - directionalLayoutMargins.trailing
        }
        buttonAreaLeadingEdgeConstraint.constant = leadingInset
        buttonAreaTrailingEdgeConstraint.constant = -trailingInset
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

    private static var galleryCellConfiguration: GalleryRailCellConfiguration = {
        // On iOS 26 selected thumbnail doesn't have a border, but instead
        // it has some extra space around it. Similar to what Photos app does.
        let borderColor: UIColor
        let borderWidth: CGFloat
        let extraPadding: CGFloat
        if #available(iOS 26, *) {
            borderColor = .clear
            borderWidth = 0
            extraPadding = 8
        } else {
            borderColor = .white
            borderWidth = 2
            extraPadding = 0
        }
        return GalleryRailCellConfiguration(
            cornerRadius: 6,
            itemBorderWidth: 0,
            itemBorderColor: nil,
            focusedItemBorderWidth: borderWidth,
            focusedItemBorderColor: borderColor,
            focusedItemOverlayColor: nil,
            focusedItemExtraPadding: extraPadding,
        )
    }()

    // Thumbnail strip is shown for albums (>1 media in one message):
    // iOS 26: all interface orientations.
    // Pre-iOS 26: portrait orientations only (`regular` vertical size class).
    private var showThumbnailStrip: Bool {
        if #unavailable(iOS 26), isVerticallyCompactLayout { return false }
        guard let currentMediaAlbum else { return false }
        return currentMediaAlbum.items.count > 1
    }

    // MARK: Video Playback Controls

    private func getOrCreateVideoPlaybackControlView() -> VideoPlaybackControlView {
        if let videoPlaybackControlView {
            return videoPlaybackControlView
        }
        let videoPlaybackControlView = VideoPlaybackControlView()
        videoPlaybackControlView.translatesAutoresizingMaskIntoConstraints = false
        videoPlaybackControlView.delegate = self
        videoPlaybackControlView.isHidden = true
        contentView.addSubview(videoPlaybackControlView)

        // Portrait constraints.
        let portraitConstraints = [
            videoPlaybackControlView.topAnchor.constraint(equalTo: buttonArea.topAnchor),
            videoPlaybackControlView.bottomAnchor.constraint(equalTo: buttonArea.bottomAnchor),
            videoPlaybackControlView.centerXAnchor.constraint(equalTo: buttonArea.centerXAnchor)
        ]
        videoPlayerControlsConstraintsPortrait += portraitConstraints

        // Landscape constraints.
        let landscapeConstraints = [
            videoPlaybackControlView.leadingAnchor.constraint(equalTo: videoPlayerControlsArea.leadingAnchor),
            videoPlaybackControlView.topAnchor.constraint(equalTo: videoPlayerControlsArea.topAnchor),
            videoPlaybackControlView.bottomAnchor.constraint(equalTo: videoPlayerControlsArea.bottomAnchor),
        ]
        videoPlayerControlsConstraintsLandscape += landscapeConstraints

        if isVerticallyCompactLayout {
            NSLayoutConstraint.activate(landscapeConstraints)
        } else {
            NSLayoutConstraint.activate(portraitConstraints)
        }

        self.videoPlaybackControlView = videoPlaybackControlView

        return videoPlaybackControlView
    }

    private func getOrCreateVideoPlaybackProgressView() -> PlayerProgressView {
        if let videoPlaybackProgressView {
            return videoPlaybackProgressView
        }

        let videoPlaybackProgressView = PlayerProgressView()
        videoPlaybackProgressView.isHidden = true
        videoPlaybackProgressView.translatesAutoresizingMaskIntoConstraints = false
        if let captionAndMediaControlsGlassBackgroundView {
            captionAndMediaControlsGlassBackgroundView.contentView.addSubview(videoPlaybackProgressView)
        } else {
            contentView.addSubview(videoPlaybackProgressView)
        }

        // Portrait constraints.
        let portraitConstraints = [
            videoPlaybackProgressView.topAnchor.constraint(equalTo: videoPlayerControlsArea.topAnchor),
            videoPlaybackProgressView.leadingAnchor.constraint(equalTo: videoPlayerControlsArea.leadingAnchor),
            videoPlaybackProgressView.trailingAnchor.constraint(equalTo: videoPlayerControlsArea.trailingAnchor),
            {
                let constraint = videoPlaybackProgressView.bottomAnchor.constraint(
                    equalTo: videoPlayerControlsArea.bottomAnchor
                )
                constraint.priority = .defaultHigh + 100
                return constraint
            }()
        ]
        videoPlayerControlsConstraintsPortrait += portraitConstraints

        // Landscape constraints.
        let videoPlaybackControlView = getOrCreateVideoPlaybackControlView()
        let landscapeConstraints = [
            videoPlaybackProgressView.topAnchor.constraint(equalTo: videoPlayerControlsArea.topAnchor),
            videoPlaybackProgressView.leadingAnchor.constraint(equalTo: videoPlaybackControlView.trailingAnchor, constant: 16),
            videoPlaybackProgressView.trailingAnchor.constraint(equalTo: videoPlayerControlsArea.trailingAnchor),
            videoPlaybackProgressView.bottomAnchor.constraint(equalTo: videoPlayerControlsArea.bottomAnchor),
        ]
        videoPlayerControlsConstraintsLandscape += landscapeConstraints

        if isVerticallyCompactLayout {
            NSLayoutConstraint.activate(landscapeConstraints)
        } else {
            NSLayoutConstraint.activate(portraitConstraints)
        }

        self.videoPlaybackProgressView = videoPlaybackProgressView

        return videoPlaybackProgressView
    }

    // MARK: Media Item

    private var currentItem: MediaGalleryItem?

    private var currentMediaAlbum: MediaGalleryAlbum?

    private var videoPlayer: VideoPlayer?

    func configureWithMediaItem(
        _ item: MediaGalleryItem,
        videoPlayer: VideoPlayer?,
        transitionDirection: UIPageViewController.NavigationDirection,
        animated: Bool
    ) {
        guard currentItem !== item else { return }

        currentItem = item
        if currentMediaAlbum?.items.contains(item) != true {
            currentMediaAlbum = mediaGallery.album(for: item)
        }

        var animator: UIViewPropertyAnimator?
        if animated {
            animator = UIViewPropertyAnimator(
                duration: 0.35,
                springDamping: 1,
                springResponse: 0.35
            )
        }

        // Create video playback controls if necessary.
        if let videoPlayer, item.isVideo {
            self.videoPlayer = videoPlayer

            let playerControlsView = getOrCreateVideoPlaybackControlView()
            playerControlsView.updateWithMediaItem(item)
            playerControlsView.updateStatusWithPlayer(videoPlayer)

            let playerProgressView = getOrCreateVideoPlaybackProgressView()
            playerProgressView.videoPlayer = videoPlayer
        } else {
            self.videoPlayer = nil
        }

        // Animate caption view and video player progress bar together.
        updateCaptionAndVideoControls(using: animator)

        // Don't update thumbnail strip if we're going to hide it - for better visual experience.
        if showThumbnailStrip {
            thumbnailStrip.configureCellViews(
                itemProvider: currentMediaAlbum!,
                focusedItem: item,
                cellViewBuilder: { _ in
                    return GalleryRailCellView(configuration: Self.galleryCellConfiguration)
                },
                animated: animated && thumbnailStrip.isHidden == false
            )
        }
        updateThumbnailStripLayout(using: animator, transitionDirection: transitionDirection)

        if let animator {
            animator.startAnimation()
        }
    }

    // MARK: Animations

    private func updateCaptionAndVideoControls(using animator: UIViewPropertyAnimator? = nil) {
        let captionForDisplay = currentItem?.captionForDisplay

        // Prepare current visibility state of UI elements.
        let showCaptionView = captionForDisplay?.nilIfEmpty != nil
        let showVideoPlayerControls = videoPlayer != nil
        let showThumbnailStrip = showThumbnailStrip
        let useSharedGlassBackground: Bool = {
            if isVerticallyCompactLayout {
                false
            } else if #available(iOS 26, *) {
                showCaptionView || showVideoPlayerControls
            } else {
                false
            }
        }()

        // Spacing between caption or video progress view and thumbnail strip.
        let verticalSpacing: CGFloat = {
            if #available(iOS 26, *) {
                isVerticallyCompactLayout ? 20 : 24
            } else {
                8
            }
        }()
        let captionViewAreaBottomSpacing: CGFloat = {
            if showCaptionView == false {
                0
            } else if useSharedGlassBackground {
                showVideoPlayerControls ? -8 : 0
            } else if showVideoPlayerControls || showThumbnailStrip || isVerticallyCompactLayout == false {
                verticalSpacing
            } else {
                0
            }
        }()
        let videoPlayerControlsAreaBottomSpacing: CGFloat = {
            if useSharedGlassBackground {
                verticalSpacing
            } else if showVideoPlayerControls == false {
                0
            } else if showThumbnailStrip || isVerticallyCompactLayout == false {
                verticalSpacing
            } else {
                0
            }
        }()

        // No animations.
        guard let animator else {
            // Update caption box.
            captionView.content = captionForDisplay
            if showCaptionView {
                // Just in case, make sure the view is properly configured after previous animations.
                captionView.animateIn()
            }
            captionView.isHidden = showCaptionView == false
            captionViewAreaZeroHeightConstraint.isActive = showCaptionView == false
            captionViewAreaBottomToVideoPlayerControlsAreaTop?.constant = captionViewAreaBottomSpacing

            // Update video playback controls.
            if showVideoPlayerControls {
                // Just in case, make sure the views are properly configured after previous animations.
                videoPlaybackControlView?.animateIn()
                videoPlaybackProgressView?.animateIn()
            }
            videoPlaybackControlView?.isHidden = showVideoPlayerControls == false
            videoPlaybackProgressView?.isHidden = showVideoPlayerControls == false
            videoPlayerControlsAreaZeroHeightConstraint.isActive = showVideoPlayerControls == false
            videoPlayerControlsAreaBottomToThumbnailStripTop?.constant = videoPlayerControlsAreaBottomSpacing

            // Show / hide grouped / individual glass backgrounds.
            if #available(iOS 26, *) {
                captionAndMediaControlsGlassBackgroundView?.effect = useSharedGlassBackground ? interactiveGlassEffect() : nil

                if showCaptionView {
                    captionView.hasGlassBackground = !useSharedGlassBackground
                }

                if showVideoPlayerControls {
                    videoPlaybackProgressView?.hasGlassBackground = !useSharedGlassBackground
                }
            }

            return
        }

        //
        // Step 0. Get previous visibility states for UI elements.
        //
        let isCaptionViewVisible = captionView.isEmpty == false
        let isVideoPlayerProgressViewVisible = videoPlayerControlsAreaZeroHeightConstraint.isActive == false
        let isUsingSharedGlassBackground: Bool = {
            if #available(iOS 26, *), let captionAndMediaControlsGlassBackgroundView {
                captionAndMediaControlsGlassBackgroundView.effect != nil
            } else {
                false
            }
        }()

        //
        // Step 1. Prepare views that are hidden but will be shown:
        // • update constraints to put UI elements in their final position.
        // • unhide views but set their opacity to 0.
        // • on iOS 26 remove `liqiud glass` effect.
        //
        if showCaptionView, isCaptionViewVisible == false {
            UIView.performWithoutAnimation {
                captionView.content = captionForDisplay
                if #available(iOS 26, *) {
                    captionView.hasGlassBackground = !useSharedGlassBackground
                }
                captionView.prepareToBeAnimatedIn()
            }
        }
        if showVideoPlayerControls, isVideoPlayerProgressViewVisible == false {
            UIView.performWithoutAnimation {
                if #available(iOS 26, *) {
                    videoPlaybackProgressView?.hasGlassBackground = !useSharedGlassBackground
                }
                videoPlaybackControlView?.prepareToBeAnimatedIn()
                videoPlaybackProgressView?.prepareToBeAnimatedIn()
            }
        }
        if #available(iOS 26, *), useSharedGlassBackground, isUsingSharedGlassBackground == false {
            UIView.performWithoutAnimation {
                captionAndMediaControlsGlassBackgroundView?.effect = nil

                captionViewAreaBottomToVideoPlayerControlsAreaTop?.constant = captionViewAreaBottomSpacing
                videoPlayerControlsAreaBottomToThumbnailStripTop?.constant = videoPlayerControlsAreaBottomSpacing
           }
        }

        //
        // Step 2. Animate UI elements in or out.
        // If the view is animated out layout (constraints) will be updated once animatior completes.
        //

        // Caption view.
        if showCaptionView, isCaptionViewVisible == false {
            // No caption -> Caption
            animator.addAnimations {
                self.captionView.animateIn()

                self.captionViewAreaZeroHeightConstraint.isActive = false
                self.captionViewAreaBottomToVideoPlayerControlsAreaTop?.constant = captionViewAreaBottomSpacing
            }
        } else if showCaptionView == false, isCaptionViewVisible {
            // Caption -> No caption
            animator.addAnimations {
                self.captionView.animateOut()

                self.captionViewAreaZeroHeightConstraint.isActive = true
                self.captionViewAreaBottomToVideoPlayerControlsAreaTop?.constant = captionViewAreaBottomSpacing
            }
            animator.addCompletion { position in
                guard position == .end else { return }

                self.captionView.isHidden = true
                self.captionView.content = nil
            }
        } else {
            // Caption 1 -> Caption 2
            // No caption -> no caption: possible interface rotation - padding amount might change.
            animator.addAnimations {
                if showCaptionView {
                    self.captionView.content = captionForDisplay
                }
                self.captionViewAreaZeroHeightConstraint.isActive = showCaptionView == false
                self.captionViewAreaBottomToVideoPlayerControlsAreaTop?.constant = captionViewAreaBottomSpacing
            }
        }

        // Video player controls.
        if showVideoPlayerControls, isVideoPlayerProgressViewVisible == false {
            // No controls -> Controls
            animator.addAnimations {
                self.videoPlaybackControlView?.animateIn()
                self.videoPlaybackProgressView?.animateIn()

                self.videoPlayerControlsAreaZeroHeightConstraint.isActive = false
                self.videoPlayerControlsAreaBottomToThumbnailStripTop?.constant = videoPlayerControlsAreaBottomSpacing
            }
        } else if showVideoPlayerControls == false, isVideoPlayerProgressViewVisible {
            // Controls -> No controls
            animator.addAnimations {
                self.videoPlaybackControlView?.animateOut()
                self.videoPlaybackProgressView?.animateOut()

                self.videoPlayerControlsAreaZeroHeightConstraint.isActive = true
                self.videoPlayerControlsAreaBottomToThumbnailStripTop?.constant = videoPlayerControlsAreaBottomSpacing
            }
            animator.addCompletion { position in
                guard position == .end else { return }

                self.videoPlaybackControlView?.isHidden = true
                self.videoPlaybackProgressView?.isHidden = true
            }
        } else {
            // Possible interface rotation - padding amount might change.
            animator.addAnimations {
                self.videoPlayerControlsAreaZeroHeightConstraint.isActive = showVideoPlayerControls == false
                self.videoPlayerControlsAreaBottomToThumbnailStripTop?.constant = videoPlayerControlsAreaBottomSpacing
            }
        }

        // Shared glass background.
        if #available(iOS 26, *) {
            if useSharedGlassBackground, isUsingSharedGlassBackground == false {
                // No background -> background
                animator.addAnimations {
                    self.captionAndMediaControlsGlassBackgroundView?.effect = self.interactiveGlassEffect()
                    if showCaptionView {
                        self.captionView.hasGlassBackground = false
                    }
                    if showVideoPlayerControls {
                        self.videoPlaybackProgressView?.hasGlassBackground = false
                    }
                }
            } else if useSharedGlassBackground == false, isUsingSharedGlassBackground {
                // Background -> No background
                animator.addAnimations {
                    self.captionAndMediaControlsGlassBackgroundView?.effect = nil
                    if showCaptionView {
                        self.captionView.hasGlassBackground = true
                    }
                    if showVideoPlayerControls {
                        self.videoPlaybackProgressView?.hasGlassBackground = true
                    }
                }
            }
        }
    }

    private func updateThumbnailStripLayout(
        using animator: UIViewPropertyAnimator? = nil,
        transitionDirection: UIPageViewController.NavigationDirection? = nil
    ) {

        let isThumbnailStripHidden = thumbnailStripAreaZeroHeightConstraint.isActive
        let showThumbnailStrip = showThumbnailStrip

        // No bottom padding in landscape because there are no controls below.
        let bottomPadding: CGFloat = {
            if isVerticallyCompactLayout {
                0
            } else if #available(iOS 26, *) {
                24
            } else {
                4
            }
        }()

        // Only animate changes if thumbnail strip appears or disappears.
        // Change from one album to another is animated by GalleryRailView.
        guard let animator, showThumbnailStrip == isThumbnailStripHidden else {
            thumbnailStrip.alpha = 1
            thumbnailStrip.transform = .identity
            thumbnailStrip.isHidden = !showThumbnailStrip

            thumbnailStripAreaZeroHeightConstraint.isActive = !showThumbnailStrip
            thumbnailStripAreaBottomToButtonsAreaTop?.constant = showThumbnailStrip ? bottomPadding : 0

            return
        }

        // Move the strip 20 pt horizontally while animating it in or out.
        // Translation shold be done in the same direction as media page scrolling.
        let animationTransform: CGAffineTransform
        if let transitionDirection {
            var offset: CGFloat = 20
            if transitionDirection == .reverse {
                offset = -offset
            }
            if showThumbnailStrip == false {
                offset = -offset
            }
            if traitCollection.layoutDirection == .rightToLeft {
                offset = -offset
            }
            animationTransform = .translate(.init(x: offset, y: 0))
        } else {
            animationTransform = .identity
        }

        if showThumbnailStrip {
            UIView.performWithoutAnimation {
                thumbnailStrip.alpha = 0
                thumbnailStrip.transform = animationTransform
                thumbnailStrip.isHidden = false
            }
            // Fade in.
            animator.addAnimations {
                self.thumbnailStrip.alpha = 1
                self.thumbnailStrip.transform = .identity

                self.thumbnailStripAreaZeroHeightConstraint.isActive = false
                self.thumbnailStripAreaBottomToButtonsAreaTop?.constant = bottomPadding
            }
        } else {
            // Fade out.
            animator.addAnimations {
                self.thumbnailStrip.alpha = 0
                self.thumbnailStrip.transform = animationTransform
            }
            animator.addCompletion { position in
                guard position == .end else { return }

                self.thumbnailStrip.alpha = 1
                self.thumbnailStrip.transform = .identity
                self.thumbnailStrip.isHidden = true

                self.thumbnailStripAreaZeroHeightConstraint.isActive = true
                self.thumbnailStripAreaBottomToButtonsAreaTop?.constant = 0
            }
        }
    }

    private func updateBottomButtonsLayout() {
        buttonForwardMedia.isHidden = isVerticallyCompactLayout
        buttonShareMedia.isHidden = isVerticallyCompactLayout
        buttonAreaZeroHeightConstraint.isActive = isVerticallyCompactLayout
    }

    // MARK: Bottom buttons

    private func didPressShare() {
        delegate?.mediaControlPanelDidRequestShareMedia(self)
    }

    private func didPressForward() {
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
