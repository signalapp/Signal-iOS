//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public struct SpoilerableTextConfig {
    public let text: CVTextValue?
    public let spoilerConfig: StyleDisplayConfiguration
    public let animator: SpoilerAnimator
    public let isViewVisible: Bool

    public struct Builder {
        public var text: CVTextValue??
        public var spoilerConfig: StyleDisplayConfiguration?
        public var animator: SpoilerAnimator?
        public var isViewVisible: Bool

        public init(isViewVisible: Bool) {
            self.isViewVisible = isViewVisible
            text = .none
            spoilerConfig = nil
            animator = nil
        }

        public func build() -> SpoilerableTextConfig? {
            let unwrappedText: CVTextValue?
            switch text {
            case .none:
                return nil
            case .some(let wrapped):
                unwrappedText = wrapped
            }
            guard let spoilerConfig, let animator else {
                return nil
            }
            return .init(
                text: unwrappedText,
                spoilerConfig: spoilerConfig,
                animator: animator,
                isViewVisible: isViewVisible
            )
        }
    }

    private init(
        text: CVTextValue?,
        spoilerConfig: StyleDisplayConfiguration,
        animator: SpoilerAnimator,
        isViewVisible: Bool
    ) {
        self.text = text
        self.spoilerConfig = spoilerConfig
        self.animator = animator
        self.isViewVisible = isViewVisible
    }
}

public class SpoilerableLabelAnimator {

    private weak var label: UILabel?
    private var text: CVTextValue?
    private var spoilerConfig: StyleDisplayConfiguration?

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
        self.spoilerConfig = config.spoilerConfig

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

extension SpoilerableLabelAnimator: SpoilerableViewAnimator {

    public var spoilerableView: UIView? { label }

    public var spoilerColor: UIColor { spoilerConfig?.textColor.forCurrentTheme ?? .clear }

    public func spoilerFrames() -> [CGRect] {
        guard let text, let label, let spoilerConfig else {
            return []
        }
        return Self.spoilerFrames(
            text: text,
            spoilerConfig: spoilerConfig,
            label: label,
            labelBounds: label.bounds.size
        )
    }

    public var spoilerFramesCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(text)
        spoilerConfig?.hashForSpoilerFrames(into: &hasher)
        hasher.combine(label?.bounds.width)
        hasher.combine(label?.bounds.height)
        return hasher.finalize()
    }

    // Every input here should be represented in the cache key above.
    private static func spoilerFrames(
        text: CVTextValue,
        spoilerConfig: StyleDisplayConfiguration,
        label: UILabel,
        labelBounds: CGSize
    ) -> [CGRect] {
        switch text {
        case .text, .attributedText:
            return []
        case .messageBody(let messageBody):
            let spoilerRanges = messageBody.spoilerRangesForAnimation(config: spoilerConfig)
            let frames = label.boundingRects(ofCharacterRanges: spoilerRanges)
            return frames
        }
    }
}
