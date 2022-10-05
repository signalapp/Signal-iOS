//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalCoreKit
import UIKit

open class RoundMediaButton: UIButton {

    public enum BackgroundStyle {
        case none
        case solid(UIColor)
        case blur(UIBlurEffect.Style)

        public static let blur: BackgroundStyle = .blur(.dark)
        public static let blurLight: BackgroundStyle = .blur(.light)
    }

    let backgroundStyle: BackgroundStyle
    private var backgroundContainerView: UIView?
    private let backgroundView: UIView?
    private var backgroundDimmerView: UIView?
    public static let defaultBackgroundColor = UIColor.ows_gray80
    static let visibleButtonSize: CGFloat = 42
    private static let defaultInset: CGFloat = 8
    private static let defaultContentInset: CGFloat = 15

    public convenience init(image: UIImage?, backgroundStyle: BackgroundStyle) {
        self.init(image: image, backgroundStyle: backgroundStyle, customView: nil)
    }

    public convenience init(customView: UIView, backgroundStyle: BackgroundStyle) {
        self.init(image: nil, backgroundStyle: backgroundStyle, customView: customView)
    }

    public init(image: UIImage?, backgroundStyle: BackgroundStyle, customView: UIView?) {
        self.backgroundStyle = backgroundStyle
        self.backgroundView = {
            switch backgroundStyle {
            case .none:
                return nil

            case .solid:
                return UIView()

            case .blur(let style):
                return UIVisualEffectView(effect: UIBlurEffect(style: style))
            }
        }()

        super.init(frame: CGRect(origin: .zero, size: .square(Self.visibleButtonSize + 2*Self.defaultInset)))

        contentEdgeInsets = UIEdgeInsets(margin: Self.defaultContentInset)
        layoutMargins = UIEdgeInsets(margin: Self.defaultInset)
        tintColor = Theme.darkThemePrimaryColor
        insetsLayoutMarginsFromSafeArea = false

        setCompressionResistanceHigh()

        if backgroundView != nil || customView != nil {
            let backgroundContainerView = PillView()
            backgroundContainerView.isUserInteractionEnabled = false
            addSubview(backgroundContainerView)
            backgroundContainerView.autoPinEdgesToSuperviewMargins()
            self.backgroundContainerView = backgroundContainerView

            if let backgroundView = backgroundView {
                backgroundView.isUserInteractionEnabled = false
                backgroundContainerView.addSubview(backgroundView)
                backgroundView.autoPinEdgesToSuperviewEdges()
            }

            if let customView = customView {
                backgroundContainerView.addSubview(customView)
                customView.autoCenterInSuperview()
            }

            let backgroundDimmerView = UIView(frame: backgroundContainerView.bounds)
            // Match color of the highlighted white button image.
            backgroundDimmerView.backgroundColor = UIColor(white: 0, alpha: 0.467)
            backgroundDimmerView.alpha = 0
            backgroundContainerView.addSubview(backgroundDimmerView)
            backgroundDimmerView.autoPinEdgesToSuperviewEdges()
            self.backgroundDimmerView = backgroundDimmerView
        }

        setImage(image, for: .normal)

        if case .solid(let color) = backgroundStyle {
            setBackgroundColor(color, for: .normal)
        }
    }

    @available(*, unavailable, message: "Use init(image:backgroundStyle:) instead")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    @available(*, unavailable, message: "Use init(image:backgroundStyle:) instead")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let backgroundContainerView = backgroundContainerView {
            sendSubviewToBack(backgroundContainerView)
        }
    }

    private var backgroundColors: [ UIControl.State.RawValue: UIColor ] = [:]

    public func setBackgroundColor(_ color: UIColor?, for state: UIControl.State) {
        if let color = color {
            backgroundColors[state.rawValue] = color
        } else {
            backgroundColors.removeValue(forKey: state.rawValue)
        }
        if self.state == state {
            updateBackgroundColor()
        }
    }

    public func backgroundColor(for state: UIControl.State) -> UIColor? {
        return backgroundColors[state.rawValue]
    }

    private func updateBackgroundColor() {
        // Use default dimming if separate background color for 'highlighted' isn't specified.
        if backgroundColor(for: .highlighted) == nil {
            backgroundDimmerView?.alpha = isHighlighted ? 1 : 0
        }

        switch backgroundStyle {
        case .solid:
            backgroundView?.backgroundColor = backgroundColor(for: state) ?? backgroundColor(for: .normal)

        default:
            break
        }
    }

    public override var isHighlighted: Bool {
        didSet {
            updateBackgroundColor()
        }
    }

    public override var isSelected: Bool {
        didSet {
            updateBackgroundColor()
        }
    }

    public override var isEnabled: Bool {
        didSet {
            updateBackgroundColor()
        }
    }
}
