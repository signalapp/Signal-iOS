//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class MediaCaptionView: UIView, SpoilerRevealStateObserver {

    private let spoilerReveal: SpoilerRevealState

    public enum Content: Equatable {
        case attachmentStreamCaption(String)
        case messageBody(HydratedMessageBody, InteractionSnapshotIdentifier)

        func attributedString(spoilerReveal: SpoilerRevealState) -> NSAttributedString {
            switch self {
            case .attachmentStreamCaption(let string):
                return NSAttributedString(string: string)
            case .messageBody(let messageBody, let interactionIdentifier):
                return messageBody.asAttributedStringForDisplay(
                    config: HydratedMessageBody.DisplayConfiguration(
                        mention: .mediaCaption,
                        style: .mediaCaption(revealedSpoilerIds: spoilerReveal.revealedSpoilerIds(interactionIdentifier: interactionIdentifier)),
                        searchRanges: nil
                    ),
                    baseAttributes: [
                        .font: MentionDisplayConfiguration.mediaCaption.font,
                        .foregroundColor: MentionDisplayConfiguration.mediaCaption.foregroundColor.forCurrentTheme
                    ],
                    isDarkThemeEnabled: Theme.isDarkThemeEnabled
                )
            }
        }

        var nilIfEmpty: Content? {
            switch self {
            case .attachmentStreamCaption(let string):
                return string.isEmpty ? nil : self
            case .messageBody(let messageBody, let identifier):
                return messageBody.nilIfEmpty.map { .messageBody($0, identifier) }
            }
        }

        var interactionIdentifier: InteractionSnapshotIdentifier? {
            switch self {
            case .attachmentStreamCaption:
                return nil
            case .messageBody(_, let id):
                return id
            }
        }
    }

    var content: Content? {
        didSet {
            guard content != oldValue else {
                return
            }
            captionTextView.attributedText = content?.attributedString(spoilerReveal: spoilerReveal)

            if oldValue?.interactionIdentifier != content?.interactionIdentifier {
                oldValue?.interactionIdentifier.map {
                    spoilerReveal.removeObserver(for: $0, observer: self)
                }
                content?.interactionIdentifier.map {
                    spoilerReveal.observeChanges(for: $0, observer: self)
                }
            }
        }
    }

    var hasNilOrEmptyContent: Bool {
        return content?.nilIfEmpty == nil
    }

    var canBeExpanded: Bool {
        captionTextView.canBeExpanded
    }

    var isExpanded: Bool {
        get { captionTextView.isExpanded }
        set { captionTextView.isExpanded = newValue }
    }

    // MARK: Interactive Transition

    private(set) var isTransitionInProgress: Bool = false

    func beginInteractiveTransition(content: Content?) {
        // Do not start the transition if next item's caption is the same as current one's.
        guard self.content != content else {
            owsAssertDebug(!isTransitionInProgress)
            isTransitionInProgress = false
            return
        }

        isTransitionInProgress = true
        heightConstraint.isActive = true
        pendingCaptionTextView.attributedText = content?.attributedString(spoilerReveal: spoilerReveal)
        updateTransitionProgress(0)
    }

    func updateTransitionProgress(_ progress: CGFloat) {
        // Do nothing until transition has been started explicitly.
        // This tweak fixes minor UI imperfections when quickly scrolling between items.
        guard isTransitionInProgress else { return }

        captionTextView.alpha = 1 - progress
        pendingCaptionTextView.alpha = progress

        // This constraint defines height of `MediaCaptionView` during
        // an interactive transition from one caption to another.
        // The constraint has a `required` priority and will
        // override constraint on the bottom edge of the `currentCaptionView`,
        // making "current" text slide up or down while being attached to
        // the top edge of `MediaCaptionView`.
        let currentViewHeight = captionTextView.intrinsicContentSize.height
        let pendingViewHeight = pendingCaptionTextView.intrinsicContentSize.height
        heightConstraint.constant = CGFloatLerp(currentViewHeight, pendingViewHeight, progress)
    }

    func finishInteractiveTransition(_ isTransitionComplete: Bool) {
        guard isTransitionInProgress else { return }

        captionTextView.alpha = 1
        if isTransitionComplete {
            captionTextView.isExpanded = false
            captionTextView.text = pendingCaptionTextView.text
        }

        pendingCaptionTextView.alpha = 0
        pendingCaptionTextView.text = nil

        heightConstraint.isActive = false

        isTransitionInProgress = false
    }

    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    // MARK: Initializers

    init(
        frame: CGRect = .zero,
        spoilerReveal: SpoilerRevealState
    ) {
        self.spoilerReveal = spoilerReveal
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        clipsToBounds = true

        addSubview(captionTextView)
        captionTextView.autoPinWidthToSuperviewMargins()
        captionTextView.autoPinEdge(toSuperviewEdge: .top)
        // This constraint is designed to be overridden by `heightConstraint`
        // during interactive transition between captions.
        // At the same time it must have a priority high enough
        // so that `currentCaptionView` defines height of the `MediaCaptionView`.
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            captionTextView.autoPinEdge(toSuperviewEdge: .bottom)
        }

        pendingCaptionTextView.alpha = 0
        addSubview(pendingCaptionTextView)
        pendingCaptionTextView.autoPinWidthToSuperviewMargins()
        pendingCaptionTextView.autoPinEdge(toSuperviewEdge: .top)
        // `pendingCaptionView` does not have constraint for the bottom edge
        // because we want the "pending" text to have its final height
        // while we slide it up during interactive transition between captions.
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleTap(_ gestureRecognizer: UITapGestureRecognizer) -> Bool {
        guard !isTransitionInProgress else { return false }

        let messageBody: HydratedMessageBody
        let interactionIdentifier: InteractionSnapshotIdentifier
        switch content {
        case .none, .attachmentStreamCaption:
            return false
        case .messageBody(let body, let id):
            messageBody = body
            interactionIdentifier = id
        }

        let location = gestureRecognizer.location(in: captionTextView).offsetBy(
            dx: -Self.captionTextContainerInsets.left,
            dy: -Self.captionTextContainerInsets.top
        )
        guard let characterIndex = captionTextView.characterIndex(of: location) else {
            return false
        }

        for item in messageBody.tappableItems(
            revealedSpoilerIds: spoilerReveal.revealedSpoilerIds(interactionIdentifier: interactionIdentifier),
            dataDetector: nil /* Maybe in the future we should detect links here. We never have, before. */
        ) {
            switch item {
            case .data, .mention:
                continue
            case .unrevealedSpoiler(let unrevealedSpoiler):
                if unrevealedSpoiler.range.contains(characterIndex) {
                    spoilerReveal.setSpoilerRevealed(
                        withID: unrevealedSpoiler.id,
                        interactionIdentifier: interactionIdentifier
                    )
                    return true
                }
            }
        }
        return false
    }

    func didUpdateRevealedSpoilers() {
        captionTextView.attributedText = content?.attributedString(spoilerReveal: spoilerReveal)
    }

    // MARK: Subviews

    private static let captionTextContainerInsets = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)

    private class func buildCaptionTextView() -> CaptionTextView {
        let textView = CaptionTextView()
        textView.font = MentionDisplayConfiguration.mediaCaption.font
        textView.textColor = MentionDisplayConfiguration.mediaCaption.foregroundColor.forCurrentTheme
        textView.backgroundColor = .clear
        textView.textContainerInset = Self.captionTextContainerInsets
        return textView
    }
    private var captionTextView = MediaCaptionView.buildCaptionTextView()
    private var pendingCaptionTextView = MediaCaptionView.buildCaptionTextView()

    private class CaptionTextView: UITextView, NSLayoutManagerDelegate {

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)

            isEditable = false
            isSelectable = false
            self.textContainer.lineBreakMode = .byTruncatingTail
            self.layoutManager.delegate = self
            updateIsScrollEnabled()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private var originalAttributedText: NSAttributedString?

        override var attributedText: NSAttributedString! {
            get {
                return super.attributedText
            }
            set {
                self.originalAttributedText = newValue
                super.attributedText = newValue
                invalidateCachedSizes()
            }
        }

        override var text: String! {
            didSet {
                invalidateCachedSizes()
            }
        }

        override var font: UIFont? {
            didSet {
                invalidateCachedSizes()
            }
        }

        override var bounds: CGRect {
            didSet {
                if oldValue.width != bounds.width {
                    invalidateCachedSizes()
                }
            }
        }

        override var frame: CGRect {
            didSet {
                if oldValue.width != bounds.width {
                    invalidateCachedSizes()
                }
            }
        }

        // MARK: -

        var canBeExpanded: Bool {
            collapsedSize.height != expandedSize.height
        }

        private var _isExpanded: Bool = false
        var isExpanded: Bool {
            get {
                guard canBeExpanded else { return false }
                return _isExpanded
            }
            set {
                guard _isExpanded != newValue else { return }
                _isExpanded = canBeExpanded ? newValue : false
                invalidateIntrinsicContentSize()
                needsTruncationComputation = true
                updateIsScrollEnabled()
            }
        }

        private func updateIsScrollEnabled() {
            isScrollEnabled = isExpanded
        }

        // MARK: Layout metrics

        private static let maxHeight: CGFloat = ScaleFromIPhone5(200)
        private static let collapsedNumberOfLines = 3

        private var collapsedSize: CGSize = .zero // 3 lines of text
        private var expandedSize: CGSize = .zero  // height is limited to `maxHeight`
        private var fullSize: CGSize = .zero

        override var intrinsicContentSize: CGSize {
            guard !text.isEmptyOrNil else {
                return CGSize(width: UIView.noIntrinsicMetric, height: 0)
            }

            calculateSizesIfNecessary()

            let textSize = isExpanded ? expandedSize : collapsedSize
            return CGSize(
                width: textContainerInset.left + textSize.width + textContainerInset.right,
                height: textContainerInset.top + textSize.height + textContainerInset.bottom
            )
        }

        private func invalidateCachedSizes() {
            collapsedSize = .zero
            expandedSize = .zero
            fullSize = .zero
            needsTruncationComputation = true

            invalidateIntrinsicContentSize()
        }

        private func calculateSizesIfNecessary() {
            guard !collapsedSize.isNonEmpty else { return }
            guard !text.isEmptyOrNil else { return }

            let maxWidth: CGFloat
            if frame.width > 0 {
                maxWidth = frame.width - textContainerInset.left - textContainerInset.right
            } else {
                maxWidth = .greatestFiniteMagnitude
            }

            // 3 lines of text.
            let collapsedTextConfig = CVTextLabel.Config(
                attributedString: attributedText,
                font: font ?? .dynamicTypeBodyClamped,
                textColor: textColor ?? .white,
                selectionStyling: [:],
                textAlignment: textAlignment,
                lineBreakMode: .byWordWrapping,
                numberOfLines: Self.collapsedNumberOfLines,
                items: []
            )
            collapsedSize = CVTextLabel.measureSize(config: collapsedTextConfig, maxWidth: maxWidth).size

            // 9 lines of text or `maxHeight`, whichever is smaller.
            let expandedTextConfig = CVTextLabel.Config(
                attributedString: attributedText,
                font: font ?? .dynamicTypeBodyClamped,
                textColor: textColor ?? .white,
                selectionStyling: [:],
                textAlignment: textAlignment,
                lineBreakMode: .byWordWrapping,
                numberOfLines: 3 * Self.collapsedNumberOfLines,
                items: []
            )
            let expandedTextSize = CVTextLabel.measureSize(config: expandedTextConfig, maxWidth: maxWidth).size
            expandedSize = CGSize(width: expandedTextSize.width, height: min(expandedTextSize.height, Self.maxHeight))

            // Unrestricted text height is necessary so that we could enable scrolling in the text view.
            let fullTextConfig = CVTextLabel.Config(
                attributedString: attributedText,
                font: font ?? .dynamicTypeBodyClamped,
                textColor: textColor ?? .white,
                selectionStyling: [:],
                textAlignment: textAlignment,
                lineBreakMode: .byWordWrapping,
                numberOfLines: 0,
                items: []
            )
            fullSize = CVTextLabel.measureSize(config: fullTextConfig, maxWidth: maxWidth).size
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            didCompleteLayoutFor textContainer: NSTextContainer?,
            atEnd layoutFinishedFlag: Bool
        ) {
            reapplyTruncationIndexIfNecessary()
        }

        private var needsTruncationComputation = true

        /// This madness is necessary because of a bug in UITextView; any .backgroundColor attributes
        /// on a UITextView's attributedText property misbehave when truncated. They get applied to
        /// the truncation character (an ellipses) when the range containing them is cut off.
        /// To remedy this, we find the truncation point, and reset our attributed string past that
        /// point, removing all its attributes except font size (for sizing) and foreground color
        /// (so the ellipses is the right color).
        /// We have to then watch for when we do this computation again, basically whenever
        /// the bounds or contents change.
        private func reapplyTruncationIndexIfNecessary() {
            guard
                needsTruncationComputation,
                let attributedText = originalAttributedText
            else {
                return
            }
            let entireGlyphRange = layoutManager.glyphRange(for: textContainer)
            var lastLineLocation = -1
            layoutManager.enumerateLineFragments(
                forGlyphRange: entireGlyphRange,
                using: { _, _, _, range, _ in
                    lastLineLocation = range.location
                }
            )
            guard lastLineLocation != -1 else {
                return
            }
            let truncationGlyphIndex = layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lastLineLocation).location
            guard truncationGlyphIndex > 0, truncationGlyphIndex < entireGlyphRange.upperBound - 1 else {
                super.attributedText = attributedText
                return
            }
            let truncationIndex = layoutManager.characterIndexForGlyph(at: truncationGlyphIndex)
            guard truncationIndex > 0, truncationIndex < attributedText.length - 1 else {
                super.attributedText = attributedText
                return
            }
            needsTruncationComputation = false
            super.attributedText = attributedText.attributedSubstring(
                from: NSRange(
                    location: 0,
                    length: truncationIndex
                )
            ) + NSAttributedString(
                string: attributedText.string.substring(from: truncationIndex),
                attributes: [
                    .font: MentionDisplayConfiguration.mediaCaption.font,
                    .foregroundColor: MentionDisplayConfiguration.mediaCaption.foregroundColor.forCurrentTheme
                ]
            )
            calculateSizesIfNecessary()
        }
    }
}
