//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class GroupCallTooltip: TooltipView {
    @objc
    public class func present(fromView: UIView,
                              widthReferenceView: UIView,
                              tailReferenceView: UIView,
                              wasTappedBlock: (() -> Void)?) -> GroupCallTooltip {
        return GroupCallTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString(
            "GROUP_CALL_START_TOOLTIP",
            comment: "Tooltip highlighting group calls."
        )
        label.font = UIFont.ows_dynamicTypeSubheadline
        label.textColor = UIColor.ows_white

        return horizontalStack(forSubviews: [label])
    }

    public override var bubbleColor: UIColor { .ows_accentGreen }

    public override var tailDirection: TooltipView.TailDirection { .up }
}
