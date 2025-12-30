//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class ViewOnceTooltip: TooltipView {

    override private init(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        wasTappedBlock: (() -> Void)?,
    ) {

        super.init(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public class func present(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        wasTappedBlock: (() -> Void)?,
    ) -> ViewOnceTooltip {
        return ViewOnceTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    override public func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "VIEW_ONCE_MESSAGES_TOOLTIP",
            comment: "Tooltip highlighting the view once messages button.",
        )
        label.font = UIFont.dynamicTypeSubheadline
        label.textColor = UIColor.ows_white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        return horizontalStack(forSubviews: [label])
    }

    override public var bubbleColor: UIColor {
        return UIColor.ows_accentBlue
    }

    override public var bubbleInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 13, left: 12, bottom: 13, right: 12)
    }

    override public var bubbleHSpacing: CGFloat {
        return 10
    }
}
