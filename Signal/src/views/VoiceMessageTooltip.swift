//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class VoiceMessageTooltip: TooltipView {

    class func present(fromView: UIView,
                       widthReferenceView: UIView,
                       tailReferenceView: UIView,
                       wasTappedBlock: (() -> Void)?) -> VoiceMessageTooltip {
        return VoiceMessageTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "VOICE_MESSAGE_TOO_SHORT_TOOLTIP",
            comment: "Message for the tooltip indicating the 'voice message' needs to be held to be held down to record."
        )
        label.font = UIFont.dynamicTypeBodyClamped
        label.textColor = Theme.primaryTextColor

        return horizontalStack(forSubviews: [label])
    }

    override var bubbleColor: UIColor { Theme.backgroundColor }
    override var bubbleHSpacing: CGFloat { 8 }
    override var tailDirection: TooltipView.TailDirection { .down }
}
