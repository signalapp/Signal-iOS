//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class VoiceMessageTooltip: TooltipView {
    @objc
    public class func present(fromView: UIView,
                              widthReferenceView: UIView,
                              tailReferenceView: UIView,
                              wasTappedBlock: (() -> Void)?) -> VoiceMessageTooltip {
        return VoiceMessageTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString(
            "VOICE_MESSAGE_TOO_SHORT_TOOLTIP",
            comment: "Message for the tooltip indicating the 'voice message' needs to be held to be held down to record."
        )
        label.font = UIFont.ows_dynamicTypeBodyClamped
        label.textColor = Theme.primaryTextColor

        return horizontalStack(forSubviews: [label])
    }

    public override var bubbleColor: UIColor { Theme.backgroundColor }
    public override var bubbleHSpacing: CGFloat { 8 }

    public override var tailDirection: TooltipView.TailDirection { .down }
}
