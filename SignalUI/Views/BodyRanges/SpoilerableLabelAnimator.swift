//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public struct SpoilerableTextConfig {
    public let text: CVTextValue?
    public let displayConfig: HydratedMessageBody.DisplayConfiguration
    public let animator: SpoilerAnimator
    public let isViewVisible: Bool

    public struct Builder {
        public var text: CVTextValue??
        public var displayConfig: HydratedMessageBody.DisplayConfiguration?
        public var animator: SpoilerAnimator?
        public var isViewVisible: Bool

        public init(isViewVisible: Bool) {
            self.isViewVisible = isViewVisible
            text = .none
            displayConfig = nil
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
            guard let displayConfig, let animator else {
                return nil
            }
            return .init(
                text: unwrappedText,
                displayConfig: displayConfig,
                animator: animator,
                isViewVisible: isViewVisible
            )
        }
    }

    private init(
        text: CVTextValue?,
        displayConfig: HydratedMessageBody.DisplayConfiguration,
        animator: SpoilerAnimator,
        isViewVisible: Bool
    ) {
        self.text = text
        self.displayConfig = displayConfig
        self.animator = animator
        self.isViewVisible = isViewVisible
    }
}

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
                transform: SpoilerFrame.init(frame:color:)
            )
        }
    }
}
