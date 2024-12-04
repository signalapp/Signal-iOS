//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreMedia
import Foundation
import SafariServices
import SignalServiceKit
import SignalUI
import UIKit
import YYImage

protocol StoryItemMediaViewDelegate: ContextMenuButtonDelegate {
    func storyItemMediaViewWantsToPause(_ storyItemMediaView: StoryItemMediaView)
    func storyItemMediaViewWantsToPlay(_ storyItemMediaView: StoryItemMediaView)

    func storyItemMediaViewShouldBeMuted(_ storyItemMediaView: StoryItemMediaView) -> Bool

    var contextMenuGenerator: StoryContextMenuGenerator { get }
    var context: StoryContext { get }
}

class StoryItemMediaView: UIView {
    weak var delegate: StoryItemMediaViewDelegate?
    public private(set) var item: StoryItem

    private let spoilerState: SpoilerRenderState

    private lazy var gradientProtectionView = GradientView(colors: [])
    private var gradientProtectionViewHeightConstraint: NSLayoutConstraint?

    private var contextButton: ContextMenuButton!
    private let bottomContentVStack = UIStackView()

    init(
        item: StoryItem,
        contextButton: ContextMenuButton,
        spoilerState: SpoilerRenderState,
        delegate: StoryItemMediaViewDelegate
    ) {
        self.item = item
        self.spoilerState = spoilerState
        self.delegate = delegate

        super.init(frame: .zero)

        autoPin(toAspectRatio: 9/16)

        updateMediaView()

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            layer.cornerRadius = 18
            clipsToBounds = true
        }

        addSubview(gradientProtectionView)
        gradientProtectionView.autoPinWidthToSuperview()
        gradientProtectionView.autoPinEdge(toSuperviewEdge: .bottom)

        bottomContentVStack.axis = .vertical
        bottomContentVStack.spacing = 24
        addSubview(bottomContentVStack)

        bottomContentVStack.autoPinWidthToSuperview(withMargin: OWSTableViewController2.defaultHOuterMargin)

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            // iPhone with notch or iPad (views/replies rendered below media, media is in a card)
            bottomContentVStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: OWSTableViewController2.defaultHOuterMargin + 16)
        } else {
            // iPhone with home button (views/replies rendered on top of media, media is fullscreen)
            bottomContentVStack.autoPinEdge(toSuperviewEdge: .bottom, withInset: 80)
        }

        bottomContentVStack.autoPinEdge(toSuperviewEdge: .top, withInset: OWSTableViewController2.defaultHOuterMargin)

        bottomContentVStack.addArrangedSubview(.vStretchingSpacer())
        bottomContentVStack.addArrangedSubview(captionLabel)
        bottomContentVStack.addArrangedSubview(authorRow)

        updateCaption()
        updateAuthorRow(newContextButton: contextButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetPlayback() {
        videoPlayerLoopCount = 0
        videoPlayer?.seek(to: .zero)
        videoPlayer?.play()
        yyImageView?.startAnimating()
        updateTimestampText()
        bottomContentVStack.alpha = 1
        gradientProtectionView.alpha = 1
        lastTruncationWidth = nil
    }

    func updateItem(_ newItem: StoryItem, newContextButton: ContextMenuButton) {
        let oldItem = self.item
        self.item = newItem

        updateTimestampText()
        updateAuthorRow(newContextButton: newContextButton)

        // Only recreate the media view if the actual attachment changes.
        if item.attachment != oldItem.attachment {
            self.pause()
            updateMediaView()
            lastTruncationWidth = nil
            updateCaption()
        }

        updateGradientProtection()
    }

    func updateTimestampText() {
        timestampLabel.isHidden = item.message.authorAddress.isSystemStoryAddress
        timestampLabel.text = DateUtil.formatTimestampRelatively(item.message.timestamp)
    }

    func willHandleTapGesture(_ gesture: UITapGestureRecognizer) -> Bool {
        if startAttachmentDownloadIfNecessary(gesture) { return true }
        if revealSpoilerIfNecessary(gesture) { return true }
        if toggleCaptionExpansionIfNecessary(gesture) { return true }

        if let textAttachmentView = mediaView as? TextAttachmentView {
            let didHandle = textAttachmentView.willHandleTapGesture(gesture)
            if didHandle {
                if textAttachmentView.isPresentingLinkTooltip {
                    // If we presented a link, pause playback
                    delegate?.storyItemMediaViewWantsToPause(self)
                } else {
                    // If we dismissed a link, resume playback
                    delegate?.storyItemMediaViewWantsToPlay(self)
                }
            }
            return didHandle
        }

        if
            let contextButton,
            contextButton.bounds.contains(gesture.location(in: contextButton))
        {
            return true
        }

        return false
    }

    func willHandlePanGesture(_ gesture: UIPanGestureRecognizer) -> Bool {
        if
            let contextButton,
            contextButton.bounds.contains(gesture.location(in: contextButton))
        {
            return true
        }

        return false
    }

    // MARK: - Appearance

    private var isViewVisible = false {
        didSet {
            captionLabel.isViewVisible = isViewVisible
        }
    }

    func setIsViewVisible(_ isVisible: Bool) {
        self.isViewVisible = isVisible
    }

    // MARK: - Playback

    func pause(hideChrome: Bool = false, animateAlongside: (() -> Void)? = nil) {
        videoPlayer?.pause()
        yyImageView?.stopAnimating()

        if hideChrome {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.bottomContentVStack.alpha = 0
                self.gradientProtectionView.alpha = 0
                animateAlongside?()
            } completion: { _ in }
        } else {
            animateAlongside?()
        }
    }

    func play(animateAlongside: @escaping () -> Void) {
        videoPlayer?.play()
        yyImageView?.startAnimating()

        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.bottomContentVStack.alpha = 1
            self.gradientProtectionView.alpha = 1
            animateAlongside()
        } completion: { _ in

        }
    }

    var duration: CFTimeInterval {
        var duration: CFTimeInterval = 0
        var glyphCount: Int?
        switch item.attachment {
        case .pointer:
            owsFailDebug("Undownloaded attachments should not progress.")
            return 0
        case .stream(let stream):
            glyphCount = stream.caption?.glyphCount

            if let asset = videoPlayer?.avPlayer.currentItem?.asset {
                let videoDuration = CMTimeGetSeconds(asset.duration)
                if stream.isLoopingVideo {
                    // GIFs should loop 3 times, or play for 5 seconds
                    // whichever is longer.
                    duration = max(5, videoDuration * 3)
                } else {
                    // Videos should play for their duration
                    duration = videoDuration

                    // For now, we don't want to factor captions into video durations,
                    // as it would cause the video to loop leading to weird UX
                    glyphCount = nil
                }
            } else if let animatedImageDuration = (yyImageView?.image as? YYAnimatedImage)?.duration {
                // GIFs should loop 3 times, or play for 5 seconds
                // whichever is longer.
                return max(5, animatedImageDuration * 3)
            } else {
                // System stories play slightly longer.
                if item.message.authorAddress.isSystemStoryAddress {
                    // Based off glyph calculation below for the text
                    // embedded in the images in english.
                    duration = 10
                } else {
                    // At base static images should play for 5 seconds
                    duration = 5
                }
            }
        case .text(let attachment):
            switch attachment.textAttachment.textContent {
            case .empty:
                glyphCount = nil
            case .styled(let text, _):
                glyphCount = text.glyphCount
            case .styledRanges(let body):
                glyphCount = body.text.glyphCount
            }

            // As a base, all text attachments play for at least 5s,
            // even if they have no text.
            duration = 5

            // If a text attachment includes a link preview, play
            // for an additional 2s
            if attachment.textAttachment.preview != nil { duration += 2 }
        }

        // If we have a glyph count, increase the duration to allow it to be readable
        if let glyphCount = glyphCount {
            // For each bucket of glyphs after the first 15,
            // add an additional 1s of playback time.
            let fifteenGlyphBuckets = (max(0, CGFloat(glyphCount) - 15) / 15).rounded(.up)
            duration += fifteenGlyphBuckets
        }

        return duration
    }

    var elapsedTime: CFTimeInterval? {
        guard let currentTime = videoPlayer?.avPlayer.currentTime(),
                let asset = videoPlayer?.avPlayer.currentItem?.asset else { return nil }
        let loopedElapsedTime = Double(videoPlayerLoopCount) * CMTimeGetSeconds(asset.duration)
        return CMTimeGetSeconds(currentTime) + loopedElapsedTime
    }

    private func startAttachmentDownloadIfNecessary(_ gesture: UITapGestureRecognizer) -> Bool {
        // Only start downloads when the user taps in the center of the view.
        let downloadHitRegion = CGRect(
            origin: CGPoint(x: frame.center.x - 30, y: frame.center.y - 30),
            size: CGSize(square: 60)
        )
        guard downloadHitRegion.contains(gesture.location(in: self)) else { return false }
        return item.startAttachmentDownloadIfNecessary(priority: .userInitiated)
    }

    // MARK: - Author Row

    private lazy var timestampLabel = UILabel()
    private lazy var authorRow = UIStackView()
    private func updateAuthorRow(newContextButton contextButton: ContextMenuButton) {
        let (avatarView, nameLabel) = SSKEnvironment.shared.databaseStorageRef.read { (
            buildAvatarView(transaction: $0),
            buildNameLabel(transaction: $0)
        ) }

        let nameTrailingView: UIView
        let nameTrailingSpacing: CGFloat
        if item.message.authorAddress.isSystemStoryAddress {
            let icon = UIImageView(image: Theme.iconImage(.official))
            icon.contentMode = .center
            nameTrailingView = icon
            nameTrailingSpacing = 3
        } else {
            nameTrailingView = timestampLabel
            nameTrailingSpacing = 8
        }

        let metadataStackView: UIStackView

        let nameHStack = UIStackView(arrangedSubviews: [
            nameLabel,
            nameTrailingView
        ])
        nameHStack.spacing = nameTrailingSpacing
        nameHStack.axis = .horizontal
        nameHStack.alignment = .center

        if
            case .privateStory(let uniqueId) = delegate?.context,
            let privateStoryThread = SSKEnvironment.shared.databaseStorageRef.read(
                block: { TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: uniqueId, transaction: $0) }
            ),
            !privateStoryThread.isMyStory {
            // For private stories, other than "My Story", render the name of the story

            let contextIcon = UIImageView()
            contextIcon.setTemplateImageName("stories-fill-compact", tintColor: Theme.darkThemePrimaryColor)
            contextIcon.autoSetDimensions(to: .square(16))

            let contextNameLabel = UILabel()
            contextNameLabel.textColor = Theme.darkThemePrimaryColor
            contextNameLabel.font = .dynamicTypeFootnote
            contextNameLabel.text = privateStoryThread.name

            let contextHStack = UIStackView(arrangedSubviews: [
                contextIcon,
                contextNameLabel
            ])
            contextHStack.spacing = 4
            contextHStack.axis = .horizontal
            contextHStack.alignment = .center
            contextHStack.alpha = 0.8

            metadataStackView = UIStackView(arrangedSubviews: [nameHStack, contextHStack])
            metadataStackView.axis = .vertical
            metadataStackView.alignment = .leading
            metadataStackView.spacing = 1
        } else {
            metadataStackView = nameHStack
        }

        let contextButtonSize: CGFloat = 42

        authorRow.removeAllSubviews()
        authorRow.addArrangedSubviews([
            avatarView,
            .spacer(withWidth: 12),
            metadataStackView,
            .hStretchingSpacer(),
            .spacer(withWidth: contextButtonSize)
        ])
        authorRow.axis = .horizontal
        authorRow.alignment = .center

        self.contextButton = contextButton
        contextButton.tintColor = Theme.darkThemePrimaryColor
        contextButton.setImage(Theme.iconImage(.buttonMore), for: .normal)
        contextButton.contentMode = .center

        authorRow.addSubview(contextButton)
        contextButton.autoSetDimensions(to: .square(contextButtonSize))
        contextButton.autoPinEdge(toSuperviewEdge: .trailing)
        NSLayoutConstraint.activate([
            contextButton.centerYAnchor.constraint(equalTo: authorRow.centerYAnchor)
        ])

        timestampLabel.setCompressionResistanceHorizontalHigh()
        timestampLabel.setContentHuggingHorizontalHigh()
        timestampLabel.font = .dynamicTypeFootnote
        timestampLabel.textColor = Theme.darkThemePrimaryColor
        timestampLabel.alpha = 0.8
        updateTimestampText()
    }

    private func buildAvatarView(transaction: SDSAnyReadTransaction) -> UIView {
        let authorAvatarView = ConversationAvatarView(
            sizeClass: .twentyEight,
            localUserDisplayMode: .asLocalUser,
            badged: false,
            shape: .circular,
            useAutolayout: true
        )

        authorAvatarView.update(transaction) { config in
            config.dataSource = try? StoryUtil.authorAvatarDataSource(
                for: item.message,
                transaction: transaction
            )
        }

        switch item.message.context {
        case .groupId:
            guard
                let groupAvatarDataSource = try? StoryUtil.contextAvatarDataSource(
                    for: item.message,
                    transaction: transaction
                )
            else {
                owsFailDebug("Unexpectedly missing group avatar")
                return authorAvatarView
            }

            let groupAvatarView = ConversationAvatarView(
                sizeClass: .twentyEight,
                localUserDisplayMode: .asLocalUser,
                badged: false,
                shape: .circular,
                useAutolayout: true
            )
            groupAvatarView.update(transaction) { config in
                config.dataSource = groupAvatarDataSource
            }

            let avatarContainer = UIView()
            avatarContainer.addSubview(authorAvatarView)
            authorAvatarView.autoPinHeightToSuperview()
            authorAvatarView.autoPinEdge(toSuperviewEdge: .leading)

            avatarContainer.addSubview(groupAvatarView)
            groupAvatarView.autoPinHeightToSuperview()
            groupAvatarView.autoPinEdge(toSuperviewEdge: .trailing)
            groupAvatarView.autoPinEdge(.leading, to: .trailing, of: authorAvatarView, withOffset: -4)

            return avatarContainer
        case .authorAci, .privateStory, .none:
            return authorAvatarView
        }
    }

    private func buildNameLabel(transaction: SDSAnyReadTransaction) -> UIView {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = UIFont.dynamicTypeSubheadline.semibold()
        label.text = StoryUtil.authorDisplayName(
            for: item.message,
            contactsManager: SSKEnvironment.shared.contactManagerRef,
            useFullNameForLocalAddress: false,
            useShortGroupName: false,
            transaction: transaction
        )
        return label
    }

    // MARK: - Caption

    private class CaptionLabel: UILabel {

        static let desiredFont = UIFont.systemFont(ofSize: 17)
        static let minimumScaleFactor: CGFloat = 15/17

        static var minimumScaleFont: UIFont { desiredFont.withSize(desiredFont.pointSize * minimumScaleFactor) }

        static let maxCollapsedLines = 5

        public var interactionIdentifier: InteractionSnapshotIdentifier
        private let spoilerState: SpoilerRenderState

        init(
            interactionIdentifier: InteractionSnapshotIdentifier,
            spoilerState: SpoilerRenderState
        ) {
            self.interactionIdentifier = interactionIdentifier
            self.spoilerState = spoilerState
            self.spoilerConfig = .init(isViewVisible: false)
            super.init(frame: .zero)
            spoilerConfig.animationManager = spoilerState.animationManager

            super.textColor = Theme.darkThemePrimaryColor

            super.layer.shadowRadius = 48
            super.layer.shadowOpacity = 0.8
            super.layer.shadowColor = UIColor.black.cgColor
            super.layer.shadowOffset = .zero
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private var spoilerConfig: SpoilerableTextConfig.Builder {
            didSet {
                spoilerAnimator.updateAnimationState(spoilerConfig)
            }
        }

        private lazy var spoilerAnimator = SpoilerableLabelAnimator(label: self)

        var isViewVisible: Bool = false {
            didSet {
                spoilerConfig.isViewVisible = isViewVisible
            }
        }

        func stopAnimatingSpoiler() {
            spoilerConfig.isViewVisible = false
        }

        func resumeAnimatingSpoiler() {
            spoilerConfig.isViewVisible = isViewVisible
        }

        @available(*, unavailable)
        override var text: String? {
            get { return super.text }
            set { super.text = newValue }
        }

        @available(*, unavailable)
        override var attributedText: NSAttributedString? {
            get { return super.attributedText }
            set { super.attributedText = newValue }
        }

        @available(*, unavailable)
        override var font: UIFont! {
            get { return super.font }
            set { super.font = newValue }
        }

        var isTruncated: Bool = false

        var tappableItems = [HydratedMessageBody.TappableItem]()

        public func setBody(_ body: StyleOnlyMessageBody?, isTruncated: Bool) {
            guard let body else {
                super.attributedText = nil
                spoilerConfig.text = nil
                spoilerConfig.displayConfig = nil
                return
            }

            let actualFont: UIFont
            if isTruncated {
                actualFont = Self.minimumScaleFont
                super.numberOfLines = Self.maxCollapsedLines
            } else {
                let actualFontSize = self.actualFontSize(body: body)
                actualFont = Self.desiredFont.withSize(actualFontSize)
                super.numberOfLines = 0
            }
            super.font = actualFont

            let hydratedBody = body.asHydratedMessageBody()
            spoilerConfig.text = .messageBody(hydratedBody)

            let revealedSpoilerIds = self.spoilerState.revealState.revealedSpoilerIds(
                interactionIdentifier: interactionIdentifier
            )
            let config = HydratedMessageBody.DisplayConfiguration.storyCaption(
                font: actualFont,
                revealedSpoilerIds: revealedSpoilerIds
            )
            self.tappableItems = hydratedBody.tappableItems(
                revealedSpoilerIds: revealedSpoilerIds,
                dataDetector: nil
            )
            spoilerConfig.text = .messageBody(hydratedBody)
            spoilerConfig.displayConfig = config
            super.attributedText = body.asAttributedStringForDisplay(
                config: config.style,
                baseFont: config.baseFont,
                baseTextColor: config.baseTextColor.forCurrentTheme,
                isDarkThemeEnabled: Theme.isDarkThemeEnabled
            )

        }

        private func actualFontSize(body: StyleOnlyMessageBody) -> CGFloat {
            let drawingContext = NSStringDrawingContext()
            drawingContext.minimumScaleFactor = Self.minimumScaleFactor
            let attributedTextForSizing = body.asAttributedStringForDisplay(
                config: HydratedMessageBody.DisplayConfiguration.storyCaption(
                    font: Self.desiredFont,
                    revealedSpoilerIds: Set() // irrelevant for sizing.
                ).style,
                isDarkThemeEnabled: false // irrelevant for sizing.
            )
            attributedTextForSizing.boundingRect(
                with: bounds.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: drawingContext
            )
            return Self.desiredFont.pointSize * drawingContext.actualScaleFactor
        }
    }

    private lazy var captionLabel = CaptionLabel(
        interactionIdentifier: .fromStoryMessage(item.message),
        spoilerState: spoilerState
    )

    private var truncatedCaptionText: StyleOnlyMessageBody?
    private var isTruncationRequired: Bool { truncatedCaptionText != nil }
    private var hasCaption: Bool { item.caption != nil }

    private func updateCaption() {
        captionLabel.interactionIdentifier = .fromStoryMessage(item.message)
        recomputeCaptionTruncation()
        if !isCaptionExpanded, let truncatedCaptionText {
            captionLabel.setBody(truncatedCaptionText, isTruncated: true)
        } else {
            captionLabel.setBody(item.caption, isTruncated: false)
        }
    }

    private func revealSpoilerIfNecessary(_ gesture: UIGestureRecognizer) -> Bool {
        let labelLocation = gesture.location(in: captionLabel)
        guard
            captionLabel.bounds.contains(labelLocation),
            let tapIndex = captionLabel.characterIndex(of: labelLocation)
        else {
            return false
        }
        let spoilerItem = captionLabel.tappableItems.lazy
            .compactMap {
                switch $0 {
                case .unrevealedSpoiler(let unrevealedSpoiler):
                    return unrevealedSpoiler
                case .data, .mention:
                    return nil
                }
            }
            .first(where: {
                $0.range.contains(tapIndex)
            })
        if let spoilerItem {
            spoilerState.revealState.setSpoilerRevealed(
                withID: spoilerItem.id,
                interactionIdentifier: .fromStoryMessage(item.message)
            )
            updateCaption()
            return true
        }
        return false
    }

    private var isCaptionExpanded = false
    private var captionBackdrop: UIView?
    private func toggleCaptionExpansionIfNecessary(_ gesture: UIGestureRecognizer) -> Bool {
        guard hasCaption, isTruncationRequired else { return false }

        if !isCaptionExpanded {
            guard captionLabel.bounds.contains(gesture.location(in: captionLabel)) else { return false }
        } else if let captionBackdrop = captionBackdrop {
            guard captionBackdrop.bounds.contains(gesture.location(in: captionBackdrop)) else { return false }
        } else {
            owsFailDebug("Unexpectedly missing caption backdrop")
        }

        let isExpanding = !isCaptionExpanded
        isCaptionExpanded = isExpanding

        if isExpanding {
            self.captionBackdrop?.removeFromSuperview()
            let captionBackdrop = UIView()
            captionBackdrop.backgroundColor = .ows_blackAlpha60
            captionBackdrop.alpha = 0
            self.captionBackdrop = captionBackdrop
            insertSubview(captionBackdrop, belowSubview: bottomContentVStack)
            captionBackdrop.autoPinEdgesToSuperviewEdges()

            delegate?.storyItemMediaViewWantsToPause(self)
        } else {
            delegate?.storyItemMediaViewWantsToPlay(self)
        }

        updateCaption()

        // Hide spoilers for the animation's duration.
        captionLabel.stopAnimatingSpoiler()
        UIView.animate(withDuration: 0.2) {
            self.captionBackdrop?.alpha = isExpanding ? 1 : 0
            self.captionLabel.layoutIfNeeded()
        } completion: { _ in
            if !isExpanding {
                self.captionBackdrop?.removeFromSuperview()
                self.captionBackdrop = nil
            }
            self.captionLabel.resumeAnimatingSpoiler()
        }

        return true
    }

    private var lastTruncationWidth: CGFloat?

    private func recomputeCaptionTruncation() {
        guard let body = item.caption else {
            lastTruncationWidth = nil
            truncatedCaptionText = nil
            return
        }
        // Only update truncation if the view's width has changed.
        guard width != lastTruncationWidth else { return }
        lastTruncationWidth = width

        bottomContentVStack.layoutIfNeeded()

        self.truncatedCaptionText = Self.truncatedCaptionText(
            fullCaptionBody: body,
            labelSize: CGSize(width: captionLabel.bounds.width, height: .infinity)
        )
    }

    /// Nil means no truncation is necessary.
    private static func truncatedCaptionText(
        fullCaptionBody: StyleOnlyMessageBody,
        labelSize: CGSize
    ) -> StyleOnlyMessageBody? {
        let labelMinimumScaledFont = CaptionLabel.minimumScaleFont

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: labelSize)
        let textStorage = NSTextStorage()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let displayConfigForSizing = HydratedMessageBody.DisplayConfiguration.storyCaption(
            font: labelMinimumScaledFont,
            revealedSpoilerIds: Set() // irrelevant for sizing
        )
        let fullCaptionText = fullCaptionBody.asAttributedStringForDisplay(
            config: displayConfigForSizing.style,
            isDarkThemeEnabled: false // irrelevant for sizing
        )
        textStorage.setAttributedString(fullCaptionText)

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = CaptionLabel.maxCollapsedLines

        func visibleCaptionRange() -> NSRange {
            layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: textContainer), actualGlyphRange: nil)
        }

        var visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound

        // Check if we're displaying less than the full length of the caption text.
        guard visibleCharacterRangeUpperBound < (fullCaptionText.string as NSString).length else {
            return nil
        }

        let readMoreString = OWSLocalizedString(
            "STORIES_CAPTION_READ_MORE",
            comment: "Text indication a story caption can be tapped to read more."
        )
        let readMoreBody = StyleOnlyMessageBody(text: readMoreString, style: .bold)
        let suffix = StyleOnlyMessageBody(plaintext: "… ").addingSuffix(readMoreBody)

        var potentialTruncatedCaptionBody = fullCaptionBody
        func truncatePotentialCaptionText(to index: Int) {
            potentialTruncatedCaptionBody = potentialTruncatedCaptionBody.stripAndDropLast(
                potentialTruncatedCaptionBody.length - index
            )
        }

        func buildTruncatedCaptionText() -> StyleOnlyMessageBody {
            return potentialTruncatedCaptionBody.stripAndDropLast(0).addingSuffix(suffix)
        }

        // We might fit without further truncation, for example if the caption
        // contains new line characters, so set the possible new text immediately.
        truncatePotentialCaptionText(to: visibleCharacterRangeUpperBound)

        visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound - suffix.length

        // If we're still truncated, trim down the visible text until
        // we have space to fit the read more text without truncation.
        // This should only take a few iterations.
        var iterationCount = 0
        while visibleCharacterRangeUpperBound < potentialTruncatedCaptionBody.length {
            let truncateToIndex = max(0, visibleCharacterRangeUpperBound)
            guard truncateToIndex > 0 else { break }

            truncatePotentialCaptionText(to: truncateToIndex)

            visibleCharacterRangeUpperBound = visibleCaptionRange().upperBound - suffix.length

            iterationCount += 1
            if iterationCount >= 5 {
                owsFailDebug("Failed to calculate visible range for caption text. Bailing.")
                break
            }
        }

        return buildTruncatedCaptionText()
    }

    private func updateGradientProtection() {
        gradientProtectionViewHeightConstraint?.isActive = false

        if hasCaption {
            gradientProtectionViewHeightConstraint = gradientProtectionView.autoMatch(.height, to: .height, of: self, withMultiplier: 0.4)
            gradientProtectionView.colors = [
                .clear,
                .black.withAlphaComponent(0.8)
            ]
        } else {
            gradientProtectionViewHeightConstraint = gradientProtectionView.autoMatch(.height, to: .height, of: self, withMultiplier: 0.2)
            gradientProtectionView.colors = [
                .clear,
                .black.withAlphaComponent(0.6)
            ]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCaption()
    }

    // MARK: - Media

    private weak var mediaView: UIView?
    private func updateMediaView() {
        mediaView?.removeFromSuperview()
        videoPlayer = nil
        yyImageView = nil
        videoPlayerLoopCount = 0

        let mediaView = buildMediaView()
        self.mediaView = mediaView
        insertSubview(mediaView, at: 0)
        mediaView.autoPinEdgesToSuperviewEdges()
    }

    private func buildMediaView() -> UIView {
        switch item.attachment {
        case .stream(let stream):
            let container = UIView()

            guard let thumbnailImage = stream.attachment.attachmentStream.thumbnailImageSync(quality: .small) else {
                owsFailDebug("Failed to generate thumbnail for attachment stream")
                return buildContentUnavailableView()
            }

            let backgroundImageView = buildBackgroundImageView(thumbnailImage: thumbnailImage)
            container.addSubview(backgroundImageView)
            backgroundImageView.autoPinEdgesToSuperviewEdges()

            switch stream.attachment.attachmentStream.contentType {
            case .video:
                let videoView = buildVideoView(attachment: stream.attachment)
                container.addSubview(videoView)
                videoView.autoPinEdgesToSuperviewEdges()
            case .animatedImage:
                let yyImageView = buildYYImageView(attachment: stream.attachment.attachmentStream)
                container.addSubview(yyImageView)
                yyImageView.autoPinEdgesToSuperviewEdges()
            case .image:
                let imageView = buildImageView(attachment: stream.attachment.attachmentStream)
                container.addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            case .audio, .file, .invalid:
                owsFailDebug("Unexpected content type.")
                return buildContentUnavailableView()
            }

            return container
        case .pointer(let pointer):
            let container = UIView()

            if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer.attachment) {
                container.addSubview(blurHashImageView)
                blurHashImageView.autoPinEdgesToSuperviewEdges()
            }

            let view = buildDownloadStateView(
                for: pointer.attachment,
                transitTierDownloadState: pointer.transitTierDownloadState
            )
            container.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()

            return container
        case .text(let text):
            return TextAttachmentView(
                attachment: text,
                interactionIdentifier: .fromStoryMessage(item.message),
                spoilerState: spoilerState
            )
        }
    }

    public func updateMuteState() {
        videoPlayer?.isMuted = delegate?.storyItemMediaViewShouldBeMuted(self) ?? false
    }

    private var videoPlayerLoopCount = 0
    private var videoPlayer: VideoPlayer?
    private func buildVideoView(attachment: ReferencedAttachmentStream) -> UIView {
        guard let player = try? VideoPlayer(attachment: attachment, shouldMixAudioWithOthers: true) else {
            owsFailDebug("Could not load attachment.")
            return buildContentUnavailableView()
        }
        player.delegate = self
        self.videoPlayer = player
        updateMuteState()

        videoPlayerLoopCount = 0

        let playerView = VideoPlayerView()
        playerView.contentMode = .scaleAspectFit
        playerView.videoPlayer = player
        player.play()

        return playerView
    }

    private var yyImageView: YYAnimatedImageView?
    private func buildYYImageView(attachment: AttachmentStream) -> UIView {
        guard
            let image = try? attachment.decryptedYYImage()
        else {
            owsFailDebug("Could not load attachment.")
            return buildContentUnavailableView()
        }
        guard image.size.width > 0,
            image.size.height > 0 else {
                owsFailDebug("Attachment has invalid size.")
                return buildContentUnavailableView()
        }
        let animatedImageView = YYAnimatedImageView()
        animatedImageView.contentMode = .scaleAspectFit
        animatedImageView.layer.minificationFilter = .trilinear
        animatedImageView.layer.magnificationFilter = .trilinear
        animatedImageView.layer.allowsEdgeAntialiasing = true
        animatedImageView.image = image
        self.yyImageView = animatedImageView
        return animatedImageView
    }

    private func buildImageView(attachment: AttachmentStream) -> UIView {
        guard let image = try? attachment.decryptedImage() else {
            owsFailDebug("Could not load attachment.")
            return buildContentUnavailableView()
        }
        guard image.size.width > 0,
            image.size.height > 0 else {
                owsFailDebug("Attachment has invalid size.")
                return buildContentUnavailableView()
        }

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = image
        return imageView
    }

    private func buildBlurHashImageViewIfAvailable(pointer: AttachmentTransitPointer) -> UIView? {
        guard
            let blurHash = pointer.attachment.blurHash,
            let blurHashImage = BlurHash.image(for: blurHash)
        else {
            return nil
        }
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = blurHashImage
        return imageView
    }

    private func buildBackgroundImageView(thumbnailImage: UIImage) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.image = thumbnailImage
        imageView.clipsToBounds = true

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        imageView.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        return imageView
    }

    private static let mediaCache = CVMediaCache()
    private func buildDownloadStateView(
        for pointer: AttachmentTransitPointer,
        transitTierDownloadState: AttachmentDownloadState
    ) -> UIView {
        let progressView = CVAttachmentProgressView(
            direction: .download(
                attachmentPointer: pointer,
                transitTierDownloadState: transitTierDownloadState
            ),
            diameter: 56,
            isDarkThemeEnabled: true,
            mediaCache: Self.mediaCache
        )

        let manualLayoutView = OWSLayerView(frame: .zero) { layerView in
            progressView.frame.size = progressView.layoutSize
            progressView.center = layerView.center
        }
        manualLayoutView.addSubview(progressView)

        return manualLayoutView
    }

    private func buildContentUnavailableView() -> UIView {
        // TODO: Error state
        return UIView()
    }
}

class StoryItem: NSObject {
    let message: StoryMessage
    let numberOfReplies: UInt64
    enum Attachment: Equatable {
        struct Pointer: Equatable {
            let reference: AttachmentReference
            let attachment: AttachmentTransitPointer
            let transitTierDownloadState: AttachmentDownloadState
            var caption: String? { reference.storyMediaCaption?.text }
            var captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>] { reference.storyMediaCaption?.collapsedStyles ?? [] }

            static func == (lhs: StoryItem.Attachment.Pointer, rhs: StoryItem.Attachment.Pointer) -> Bool {
                return lhs.attachment.id == rhs.attachment.id
                    && lhs.reference.hasSameOwner(as: rhs.reference)
                    && lhs.transitTierDownloadState == rhs.transitTierDownloadState
            }
        }

        struct Stream: Equatable {
            let attachment: ReferencedAttachmentStream
            var isLoopingVideo: Bool { attachment.reference.renderingFlag == .shouldLoop }
            var caption: String? { attachment.reference.storyMediaCaption?.text }
            var captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>] { attachment.reference.storyMediaCaption?.collapsedStyles ?? [] }

            static func == (lhs: StoryItem.Attachment.Stream, rhs: StoryItem.Attachment.Stream) -> Bool {
                return lhs.attachment.attachmentStream.id == rhs.attachment.attachmentStream.id
                    && lhs.attachment.reference.hasSameOwner(as: rhs.attachment.reference)
            }
        }

        case pointer(Pointer)
        case stream(Stream)
        case text(PreloadedTextAttachment)
    }
    var attachment: Attachment

    init(message: StoryMessage, numberOfReplies: UInt64, attachment: Attachment) {
        self.message = message
        self.numberOfReplies = numberOfReplies
        self.attachment = attachment
    }

    var caption: StyleOnlyMessageBody? {
        switch attachment {
        case let .stream(stream):
            guard let text = stream.caption?.nilIfEmpty else {
                return nil
            }
            return StyleOnlyMessageBody(text: text, collapsedStyles: stream.captionStyles)
        case let .pointer(pointer):
            guard let text = pointer.caption?.nilIfEmpty else {
                return nil
            }
            return StyleOnlyMessageBody(text: text, collapsedStyles: pointer.captionStyles)
        case .text:
            return nil
        }
    }
}

extension StoryItem {
    // MARK: - Downloading

    @discardableResult
    func startAttachmentDownloadIfNecessary(priority: AttachmentDownloadPriority = .default) -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard
                case .pointer(let pointer) = attachment,
                pointer.attachment.downloadState(tx: tx.asV2Read) != .enqueuedOrDownloading
            else {
                return false
            }
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(
                message,
                priority: priority,
                tx: tx.asV2Write
            )
            return true
        }
    }

    var isPendingDownload: Bool {
        switch attachment {
        case .pointer:
            return true
        case .stream, .text:
            return false
        }
    }
}

extension StoryItemMediaView: VideoPlayerDelegate {
    func videoPlayerDidPlayToCompletion(_ videoPlayer: VideoPlayer) {
        videoPlayerLoopCount += 1
    }
}
