//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public class SpoilerableTextViewAnimator {

    private weak var textView: UITextView?
    private var text: CVTextValue?
    private var displayConfig: HydratedMessageBody.DisplayConfiguration?

    public init(textView: UITextView) {
        self.textView = textView
    }

    private var isAnimating = false

    public func updateAnimationState(_ configBuilder: SpoilerableTextConfig.Builder) {
        guard let config = configBuilder.build() else {
            return
        }
        updateAnimationState(config)
    }

    public func updateAnimationState(_ config: SpoilerableTextConfig) {
        self.text = config.text
        self.displayConfig = config.displayConfig

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
            return
        }
        if wantsToAnimate {
            config.animator.addViewAnimator(self)
            self.isAnimating = true
        } else {
            // We are stopping animations.
            config.animator.removeViewAnimator(self)
            self.isAnimating = false
        }
    }
}

// MARK: - SpoilerableViewAnimator

extension SpoilerableTextViewAnimator: SpoilerableViewAnimator {

    public var spoilerableView: UIView? { textView }

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
                textStorage: textStorage,
                layoutManager: layoutManager,
                textContainerInsets: textContainerInsets,
                transform: SpoilerFrame.init(frame:color:)
            )
        }
    }
}
