//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
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
        get {
            return captionTextView.content
        }
        set {
            let oldValue = captionTextView.content
            guard oldValue != newValue else {
                return
            }
            captionTextView.content = newValue

            if oldValue?.interactionIdentifier != newValue?.interactionIdentifier {
                oldValue?.interactionIdentifier.map {
                    spoilerReveal.removeObserver(for: $0, observer: self)
                }
                newValue?.interactionIdentifier.map {
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
        captionTextView.autoPinHeightToSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleTap(_ gestureRecognizer: UITapGestureRecognizer) -> Bool {
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

    func didUpdateRevealedSpoilers(_ spoilerReveal: SpoilerRevealState) {
        captionTextView.didUpdateRevealedSpoilers()
    }

    // MARK: Subviews

    private static let captionTextContainerInsets = UIEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)

    private class func buildCaptionTextView(spoilerReveal: SpoilerRevealState) -> CaptionTextView {
        let textView = CaptionTextView(spoilerReveal: spoilerReveal)
        textView.font = MentionDisplayConfiguration.mediaCaption.font
        textView.textColor = MentionDisplayConfiguration.mediaCaption.foregroundColor.forCurrentTheme
        textView.backgroundColor = .clear
        textView.textContainerInset = Self.captionTextContainerInsets
        return textView
    }
    private lazy var captionTextView = MediaCaptionView.buildCaptionTextView(spoilerReveal: spoilerReveal)

    private class CaptionTextView: UITextView, NSLayoutManagerDelegate {

        init(spoilerReveal: SpoilerRevealState) {
            self.spoilerReveal = spoilerReveal
            super.init(frame: .zero, textContainer: nil)

            isEditable = false
            isSelectable = false
            self.textContainer.lineBreakMode = .byTruncatingTail
            updateIsScrollEnabled()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private let spoilerReveal: SpoilerRevealState

        public var content: MediaCaptionView.Content? {
            didSet {
                super.attributedText = content?.attributedString(spoilerReveal: spoilerReveal)
                invalidateCachedSizes()
            }
        }

        public func didUpdateRevealedSpoilers() {
            // No need to recompute cached sizes; spoilers have no effect on size.
            super.attributedText = content?.attributedString(spoilerReveal: spoilerReveal)
        }

        @available(*, unavailable)
        override var attributedText: NSAttributedString! {
            didSet {}
        }

        @available(*, unavailable)
        override var text: String! {
            didSet {}
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
                updateIsScrollEnabled()
            }
        }

        private func updateIsScrollEnabled() {
            isScrollEnabled = isExpanded
        }

        // MARK: Layout metrics

        private static let maxHeight = CGFloat.scaleFromIPhone5(200)
        private static let collapsedNumberOfLines = 3

        private var collapsedSize: CGSize = .zero // 3 lines of text
        private var expandedSize: CGSize = .zero  // height is limited to `maxHeight`
        private var fullSize: CGSize = .zero

        override var intrinsicContentSize: CGSize {
            guard content?.nilIfEmpty != nil else {
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

            invalidateIntrinsicContentSize()
        }

        private func calculateSizesIfNecessary() {
            guard !collapsedSize.isNonEmpty else { return }
            guard let content = content?.nilIfEmpty else { return }

            let maxWidth: CGFloat
            if frame.width > 0 {
                maxWidth = frame.width - textContainerInset.left - textContainerInset.right
            } else {
                maxWidth = .greatestFiniteMagnitude
            }

            let attributedText = content.attributedString(spoilerReveal: spoilerReveal)

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
    }
}
