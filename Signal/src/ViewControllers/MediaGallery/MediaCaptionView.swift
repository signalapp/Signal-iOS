//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class MediaCaptionView: UIView {

    var text: String? {
        get { captionTextView.text }
        set { captionTextView.text = newValue }
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

    func beginInteractiveTransition(text: String?) {
        // Do not start the transition if next item's caption is the same as current one's.
        guard self.text != text else {
            owsAssertDebug(!isTransitionInProgress)
            isTransitionInProgress = false
            return
        }

        isTransitionInProgress = true
        heightConstraint.isActive = true
        pendingCaptionTextView.text = text
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

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        clipsToBounds = true

        addSubview(captionTextView)
        captionTextView.autoPinWidthToSuperviewMargins()
        captionTextView.autoPinEdge(toSuperviewEdge: .top)
        // This constraint is designed to be overriden by `heightConstraint`
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

    // MARK: Subviews

    private class func buildCaptionTextView() -> CaptionTextView {
        let textView = CaptionTextView()
        textView.font = UIFont.ows_dynamicTypeBodyClamped
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
        return textView
    }
    private var captionTextView = MediaCaptionView.buildCaptionTextView()
    private var pendingCaptionTextView = MediaCaptionView.buildCaptionTextView()

    private class CaptionTextView: UITextView {

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)

            isEditable = false
            isSelectable = false
            self.textContainer.lineBreakMode = .byTruncatingTail
            updateIsScrollEnabled()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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
                font: font ?? .ows_dynamicTypeBodyClamped,
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
                font: font ?? .ows_dynamicTypeBodyClamped,
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
                font: font ?? .ows_dynamicTypeBodyClamped,
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
