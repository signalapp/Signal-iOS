//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

/// Animates spoilers on a UITextView or UITextView subclass.
/// Users must hold a reference to the animator alongside the UITextView,
/// and configure it with a SpoilerableTextConfig to begin animation.
public class SpoilerableTextViewAnimator {

    private weak var textView: UITextView?
    private var text: CVTextValue?
    private var displayConfig: HydratedMessageBody.DisplayConfiguration?

    public init(textView: UITextView) {
        self.textView = textView
    }

    private var isAnimating = false
    private var animationManager: SpoilerAnimationManager?

    public func updateAnimationState(_ configBuilder: SpoilerableTextConfig.Builder) {
        guard let config = configBuilder.build() else {
            return
        }
        updateAnimationState(config)
    }

    public func updateAnimationState(_ config: SpoilerableTextConfig) {
        self.text = config.text
        self.displayConfig = config.displayConfig
        self.animationManager = config.animationManager

        let wantsToAnimate: Bool
        if config.isViewVisible, let text = config.text {
            switch text {
            case .text, .attributedText:
                wantsToAnimate = false
            case .messageBody(let body):
                wantsToAnimate = body.hasSpoilerRangesToAnimate
            }
        } else {
            wantsToAnimate = false
        }

        guard wantsToAnimate != isAnimating else {
            if isAnimating {
                config.animationManager.didUpdateAnimationState(for: self)
            }
            return
        }
        if wantsToAnimate {
            config.animationManager.addViewAnimator(self)
            self.isAnimating = true
        } else {
            // We are stopping animations.
            config.animationManager.removeViewAnimator(self)
            self.isAnimating = false
        }
    }

    /// UITextView does not like having a custom sublayer attached.
    /// Instead, we create a custom subview and add spoiler layers to it.
    /// But this means we have to manage its size; we do so by observing the
    /// text view's content size and sizing the view appropriately.
    /// Autolayout to the UITextView's bounds doesn't work for sizing
    /// to the full content size of the text view.

    private class AnimationContainerView: UIView {}

    private var textViewContentSizeObservation: NSKeyValueObservation?
    private weak var _animationContainerView: AnimationContainerView? {
        didSet {
            if _animationContainerView == nil {
                textViewContentSizeObservation = nil
            }
        }
    }

    fileprivate var animationContainerView: UIView? {
        if let _animationContainerView {
            return _animationContainerView
        }
        guard let textView else {
            return nil
        }
        let view = AnimationContainerView()
        textView.addSubview(view)
        _animationContainerView = view

        textViewContentSizeObservation = textView.observe(\.contentSize, changeHandler: { [weak self] textView, _ in
            guard let self else { return }
            // This gives us the correct size; textView.contentSize does not (even though
            // that's what we observe)
            let size = textView.sizeThatFits(textView.frame.size)
            self._animationContainerView?.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            if self.isAnimating, let animationManager = self.animationManager {
                animationManager.didUpdateAnimationState(for: self)
            }
        })

        return view
    }
}

// MARK: - SpoilerableViewAnimator

extension SpoilerableTextViewAnimator: SpoilerableViewAnimator {

    public var spoilerableView: UIView? { animationContainerView }

    public func spoilerFrames() -> [SpoilerFrame] {
        guard let text, let textView, let displayConfig else {
            return []
        }
        return Self.spoilerFrames(
            text: text,
            displayConfig: displayConfig,
            textContainer: textView.textContainer,
            textStorage: textView.textStorage,
            layoutManager: textView.layoutManager,
            textContainerInsets: textView.textContainerInset,
            textContainerBounds: textView.bounds.size
        )
    }

    public var spoilerFramesCacheKey: Int {
        var hasher = Hasher()
        hasher.combine("SpoilerableTextViewAnimator")
        hasher.combine(text)
        displayConfig?.hashForSpoilerFrames(into: &hasher)
        // Order matters. 100x10 is not the same hash value as 10x100.
        hasher.combine(textView?.textContainerInset.top)
        hasher.combine(textView?.textContainerInset.left)
        hasher.combine(textView?.bounds.width)
        hasher.combine(textView?.bounds.height)
        return hasher.finalize()
    }

    // Every input here should be represented in the cache key above.
    private static func spoilerFrames(
        text: CVTextValue,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        textContainer: NSTextContainer,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        textContainerInsets: UIEdgeInsets,
        textContainerBounds: CGSize
    ) -> [SpoilerFrame] {
        switch text {
        case .text, .attributedText:
            return []
        case .messageBody(let messageBody):
            let spoilerRanges = messageBody.spoilerRangesForAnimation(config: displayConfig)
            return textContainer.boundingRects(
                ofCharacterRanges: spoilerRanges,
                rangeMap: \.range,
                textStorage: textStorage,
                layoutManager: layoutManager,
                textContainerInsets: textContainerInsets,
                transform: { rect, spoilerRange in
                    return .init(
                        frame: rect,
                        color: spoilerRange.color,
                        style: spoilerRange.isSearchResult ? .highlight : .standard
                    )
                }
            )
        }
    }
}
