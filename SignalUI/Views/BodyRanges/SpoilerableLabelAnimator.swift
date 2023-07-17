//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

/// Defines values needed to apply spoilers to a UITextView or UILabel.
///
/// This API acknowledges that these will be shown inside table view cells which
/// may not receieve all necessary inputs together at once. The animationManager might
/// be set in the initializer or via initial view setup, but the text value will only be provided
/// at cell configuration time. Instead of requiring each user to keep its own state for each
/// required input, the config contains all inputs and can be constructed piece by piece.
///
/// The other side of this coin is callers must remember to set ALL fields eventually, or spoiler animation
/// will not start. There will be no warning or error for missing inputs; it just won't animate.
public struct SpoilerableTextConfig {
    public let text: CVTextValue?
    public let displayConfig: HydratedMessageBody.DisplayConfiguration
    public let animationManager: SpoilerAnimationManager
    public let isViewVisible: Bool

    /// Use a builder to construct a config piece by piece, and only get a config via `build()`
    /// once every piece is assembled.
    public struct Builder {
        public var text: CVTextValue??
        public var displayConfig: HydratedMessageBody.DisplayConfiguration?
        public var animationManager: SpoilerAnimationManager?
        public var isViewVisible: Bool

        public init(isViewVisible: Bool) {
            self.isViewVisible = isViewVisible
            text = .none
            displayConfig = nil
            animationManager = nil
        }

        public func build() -> SpoilerableTextConfig? {
            let unwrappedText: CVTextValue?
            switch text {
            case .none:
                return nil
            case .some(let wrapped):
                unwrappedText = wrapped
            }
            guard let displayConfig, let animationManager else {
                return nil
            }
            return .init(
                text: unwrappedText,
                displayConfig: displayConfig,
                animationManager: animationManager,
                isViewVisible: isViewVisible
            )
        }
    }

    private init(
        text: CVTextValue?,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        animationManager: SpoilerAnimationManager,
        isViewVisible: Bool
    ) {
        self.text = text
        self.displayConfig = displayConfig
        self.animationManager = animationManager
        self.isViewVisible = isViewVisible
    }
}

/// Animates spoilers on a UILabel or UILabel subclass.
/// Users must hold a reference to the animator alongside the UILabel,
/// and configure it with a SpoilerableTextConfig to begin animation.
///
/// NOTE: UILabel does not expose everything needed to determine the position of
/// characters within its bounds. This is done via an approximation; see `UILabel.boundingRects`,
/// but this may break if unusual configuration is applied to the label, or if a subclass overrides
/// rendering in an unanticipated way.
public class SpoilerableLabelAnimator {

    private weak var label: UILabel?
    private var text: CVTextValue?
    private var displayConfig: HydratedMessageBody.DisplayConfiguration?

    public init(label: UILabel) {
        self.label = label
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
            config.animationManager.addViewAnimator(self)
            self.isAnimating = true
        } else {
            // We are stopping animations.
            config.animationManager.removeViewAnimator(self)
            self.isAnimating = false
        }
    }
}

// MARK: - SpoilerableViewAnimator

extension SpoilerableLabelAnimator: SpoilerableViewAnimator {

    public var spoilerableView: UIView? { label }

    public func spoilerFrames() -> [SpoilerFrame] {
        guard let text, let label, let displayConfig else {
            return []
        }
        return Self.spoilerFrames(
            text: text,
            displayConfig: displayConfig,
            label: label,
            labelBounds: label.bounds.size
        )
    }

    public var spoilerFramesCacheKey: Int {
        var hasher = Hasher()
        hasher.combine("SpoilerableLabelAnimator")
        hasher.combine(text)
        displayConfig?.hashForSpoilerFrames(into: &hasher)
        // Order matters. 100x10 is not the same hash value as 10x100.
        hasher.combine(label?.bounds.width)
        hasher.combine(label?.bounds.height)
        return hasher.finalize()
    }

    // Every input here should be represented in the cache key above.
    private static func spoilerFrames(
        text: CVTextValue,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        label: UILabel,
        labelBounds: CGSize
    ) -> [SpoilerFrame] {
        switch text {
        case .text, .attributedText:
            return []
        case .messageBody(let messageBody):
            let spoilerRanges = messageBody.spoilerRangesForAnimation(config: displayConfig)
            return label.boundingRects(
                ofCharacterRanges: spoilerRanges,
                rangeMap: \.range,
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
