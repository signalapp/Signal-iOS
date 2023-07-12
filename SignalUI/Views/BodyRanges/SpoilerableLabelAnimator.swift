//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public class SpoilerableLabelAnimator: SpoilerableViewAnimator {

    private weak var label: UILabel?
    public var messageBody: HydratedMessageBody?
    public var spoilerConfig: StyleDisplayConfiguration

    public init(label: UILabel, spoilerConfig: StyleDisplayConfiguration) {
        self.label = label
        self.spoilerConfig = spoilerConfig
    }

    public var spoilerableView: UIView? { label }

    public var spoilerColor: UIColor { spoilerConfig.textColor.forCurrentTheme }

    public func spoilerFrames() -> [CGRect] {
        guard let messageBody, let label else {
            return []
        }
        return Self.spoilerFrames(
            messageBody: messageBody,
            spoilerConfig: spoilerConfig,
            label: label,
            labelBounds: label.bounds.size
        )
    }

    public var spoilerFramesCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(messageBody)
        spoilerConfig.hashForSpoilerFrames(into: &hasher)
        hasher.combine(label?.bounds.width)
        hasher.combine(label?.bounds.height)
        return hasher.finalize()
    }

    // Every input here should be represented in the cache key above.
    private static func spoilerFrames(
        messageBody: HydratedMessageBody,
        spoilerConfig: StyleDisplayConfiguration,
        label: UILabel,
        labelBounds: CGSize
    ) -> [CGRect] {
        let spoilerRanges = messageBody.spoilerRangesForAnimation(config: spoilerConfig)
        let frames = label.boundingRects(ofCharacterRanges: spoilerRanges)
        return frames
    }
}
