//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalCoreKit
import UIKit

public class RoundMediaButton: UIButton {

    public enum BackgroundStyle {
        case none
        case solid(UIColor)
        case blur
    }

    let backgroundStyle: BackgroundStyle
    private var backgroundContainerView: UIView?
    let backgroundView: UIView?
    private var backgroundDimmerView: UIView?
    public static let defaultBackgroundColor = UIColor.ows_gray80
    static let visibleButtonSize: CGFloat = 42
    private static let defaultInset: CGFloat = 8
    private static let defaultContentInset: CGFloat = 15

    public required init(image: UIImage?, backgroundStyle: BackgroundStyle) {
        self.backgroundStyle = backgroundStyle
        self.backgroundView = {
            switch backgroundStyle {
            case .none:
                return nil

            case .solid:
                return UIView()

            case .blur:
                return UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            }
        }()

        super.init(frame: CGRect(origin: .zero, size: .square(Self.visibleButtonSize + 2*Self.defaultInset)))

        contentEdgeInsets = UIEdgeInsets(margin: Self.defaultContentInset)
        layoutMargins = UIEdgeInsets(margin: Self.defaultInset)
        tintColor = Theme.darkThemePrimaryColor
        insetsLayoutMarginsFromSafeArea = false

        switch backgroundStyle {
        case .solid, .blur:
            backgroundContainerView = PillView()

        case .none:
            break
        }

        if let backgroundContainerView = backgroundContainerView, let backgroundView = backgroundView {
            backgroundContainerView.isUserInteractionEnabled = false
            addSubview(backgroundContainerView)
            backgroundContainerView.autoPinEdgesToSuperviewMargins()

            backgroundView.isUserInteractionEnabled = false
            backgroundContainerView.addSubview(backgroundView)
            backgroundView.autoPinEdgesToSuperviewEdges()

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
    required init?(coder: NSCoder) {
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
