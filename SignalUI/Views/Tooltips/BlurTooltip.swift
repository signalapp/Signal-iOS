//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class BlurTooltip: TooltipView {

    private override init(fromView: UIView,
                          widthReferenceView: UIView,
                          tailReferenceView: UIView,
                          wasTappedBlock: (() -> Void)?) {

        super.init(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public class func present(fromView: UIView,
                              widthReferenceView: UIView,
                              tailReferenceView: UIView,
                              wasTappedBlock: (() -> Void)?) -> BlurTooltip {
        return BlurTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString("BLUR_TOOLTIP",
                                       comment: "Tooltip highlighting the blur image editing tool.")
        label.font = UIFont.ows_dynamicTypeSubheadline
        label.textColor = UIColor.ows_white

        return horizontalStack(forSubviews: [label])
    }

    public override var bubbleColor: UIColor {
        return UIColor.ows_accentBlue
    }

    public override var tailDirection: TooltipView.TailDirection {
        return .up
    }

    public override var bubbleInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 12, bottom: 13, right: 12)
    }

    public override var bubbleHSpacing: CGFloat {
        return 10
    }
}
