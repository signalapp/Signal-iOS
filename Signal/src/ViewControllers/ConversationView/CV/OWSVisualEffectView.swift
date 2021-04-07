//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class OWSVisualEffectView: UIVisualEffectView {
    private let blurOverlay = UIView()

    struct ContentSubview {
        let subview: UIView
        let insets: UIEdgeInsets
    }

    private var contentSubviews = [ContentSubview]()

    public required init(effect: UIBlurEffect,
                         overlayBackgroundColor: UIColor) {
        super.init(effect: effect)

        blurOverlay.backgroundColor = overlayBackgroundColor
        addContentSubview(blurOverlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addContentSubview(_ subview: UIView,
                                  withInsets insets: UIEdgeInsets = .zero) {
        contentView.addSubview(subview)
        contentSubviews.append(.init(subview: subview, insets: insets))
    }

    public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                layoutSubviews()
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                layoutSubviews()
            }
        }
    }

    public override var center: CGPoint {
        didSet {
            if oldValue != center {
                layoutSubviews()
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        contentView.frame = bounds
        for contentSubview in contentSubviews {
            contentSubview.subview.frame = contentView.bounds.inset(by: contentSubview.insets)
        }
    }
}
