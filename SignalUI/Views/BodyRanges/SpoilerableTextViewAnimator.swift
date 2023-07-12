//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public class SpoilerableTextViewAnimator: SpoilerableViewAnimator {

    private weak var textView: UITextView?
    public var messageBody: HydratedMessageBody?
    public var spoilerConfig: StyleDisplayConfiguration

    public init(textView: UITextView, spoilerConfig: StyleDisplayConfiguration) {
        self.textView = textView
        self.spoilerConfig = spoilerConfig
    }

    public var spoilerableView: UIView? { textView }

    public var spoilerColor: UIColor { spoilerConfig.textColor.forCurrentTheme }

    public func spoilerFrames() -> [CGRect] {
        guard let messageBody, let textView else {
            return []
        }
        return Self.spoilerFrames(
            messageBody: messageBody,
            spoilerConfig: spoilerConfig,
            textContainer: textView.textContainer,
            textStorage: textView.textStorage,
            layoutManager: textView.layoutManager,
            textContainerInsets: textView.textContainerInset,
            textContainerBounds: textView.bounds.size
        )
    }

    public var spoilerFramesCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(messageBody)
        spoilerConfig.hashForSpoilerFrames(into: &hasher)
        hasher.combine(textView?.textContainerInset.top)
        hasher.combine(textView?.textContainerInset.left)
        hasher.combine(textView?.bounds.width)
        hasher.combine(textView?.bounds.height)
        return hasher.finalize()
    }

    // Every input here should be represented in the cache key above.
    private static func spoilerFrames(
        messageBody: HydratedMessageBody,
        spoilerConfig: StyleDisplayConfiguration,
        textContainer: NSTextContainer,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        textContainerInsets: UIEdgeInsets,
        textContainerBounds: CGSize
    ) -> [CGRect] {
        let spoilerRanges = messageBody.spoilerRangesForAnimation(config: spoilerConfig)
        var frames = textContainer.boundingRects(
            ofCharacterRanges: spoilerRanges,
            textStorage: textStorage,
            layoutManager: layoutManager
        )
        if textContainerInsets.isNonEmpty {
            frames = frames.map { frame in
                return frame.offsetBy(dx: textContainerInsets.left, dy: textContainerInsets.top)
            }
        }
        return frames
    }
}
