//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class OWSStackView: UIStackView {

    public typealias LayoutBlock = (UIView) -> Void

    public var layoutBlock: LayoutBlock?

    @objc
    public required init(name: String, arrangedSubviews: [UIView] = []) {
        super.init(frame: .zero)

        for subview in arrangedSubviews {
            addArrangedSubview(subview)
        }

        #if TESTABLE_BUILD
        self.accessibilityLabel = name
        #endif
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public override func layoutSubviews() {
        AssertIsOnMainThread()

        super.layoutSubviews()

        layoutBlock?(self)
    }

    public func reset() {
        alignment = .fill
        axis = .vertical
        spacing = 0
        isLayoutMarginsRelativeArrangement = false

        removeAllSubviews()

        layoutBlock = nil

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func apply(config: CVStackViewConfig) {
        if self.axis != config.axis {
            self.axis = config.axis
        }
        if self.alignment != config.alignment {
            self.alignment = config.alignment
        }
        if self.spacing != config.spacing {
            self.spacing = config.spacing
        }
        if self.layoutMargins != config.layoutMargins {
            self.layoutMargins = config.layoutMargins
        }
        let isLayoutMarginsRelativeArrangement = layoutMargins != .zero
        if self.isLayoutMarginsRelativeArrangement != isLayoutMarginsRelativeArrangement {
            self.isLayoutMarginsRelativeArrangement = isLayoutMarginsRelativeArrangement
        }
    }

    var asConfig: CVStackViewConfig {
        CVStackViewConfig(axis: self.axis,
                          alignment: self.alignment,
                          spacing: self.spacing,
                          layoutMargins: self.layoutMargins)
    }
}
