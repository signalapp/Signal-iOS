//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

// Compare with CVColorOrGradientView:
//
// * CVColorOrGradientView is intended to be used in CVC cells.
//   It does not assume the gradient bounds corresponds to the
//   view bounds.
// * ColorOrGradientSwatchView is for use elsewhere.
//   It can pin gradient bounds to the edges of a circle for previews.
//   It can be used to render wallpapers.
//
// Although we could combine these two views, these two scenarios are
// just different enough that its convenient to have two separate views.
public class ColorOrGradientSwatchView: ManualLayoutViewWithLayer {
    public var setting: ColorOrGradientSetting {
        didSet {
            if setting != oldValue {
                configure()
            }
        }
    }

    public enum ShapeMode {
        case circle
        case rectangle
    }
    private let shapeMode: ShapeMode

    private let themeMode: ColorOrGradientThemeMode

    private let gradientLayer = CAGradientLayer()

    public init(setting: ColorOrGradientSetting,
                shapeMode: ShapeMode,
                themeMode: ColorOrGradientThemeMode = .auto) {
        self.setting = setting
        self.shapeMode = shapeMode
        self.themeMode = themeMode

        var colorName: String?
        if #available(iOS 14.0, *) {
            switch setting {
            case .solidColor(let color),
                 .themedColor(let color, _):
                colorName = color.asUIColor.accessibilityName
            case .gradient(let gradientColor1, let gradientColor2, _),
                 .themedGradient(let gradientColor1, let gradientColor2, _, _, _):
                colorName = String(
                    format: OWSLocalizedString(
                        "WALLPAPER_GRADIENT_COLORS_ACCESSIBILITY_LABEL",
                        comment: "Accessibility label for gradient wallpaper swatch, naming the two colors in the gradient. {{ Embeds the names of the two colors in the gradient }}"
                    ),
                    gradientColor1.asUIColor.accessibilityName,
                    gradientColor2.asUIColor.accessibilityName
                )
            }
        }

        super.init(name: colorName ?? "ColorOrGradientSwatchView")

        self.shouldDeactivateConstraints = false

        self.isAccessibilityElement = true

        configure()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)

        addLayoutBlock { view in
            guard let view = view as? ColorOrGradientSwatchView else { return }
            view.gradientLayer.frame = view.bounds
            view.configure()
        }
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    @objc
    private func themeDidChange() {
        configure()
    }

    fileprivate struct State: Equatable {
        let size: CGSize
        let setting: ColorOrGradientSetting
    }
    private var state: State?

    private func configure() {
        let size = bounds.size
        let newState = State(size: size, setting: setting)
        // Exit early if the appearance and bounds haven't changed.
        guard state != newState else {
            return
        }
        self.state = newState

        switch shapeMode {
        case .circle:
            self.layer.cornerRadius = size.smallerAxis * 0.5
            self.clipsToBounds = true
        case .rectangle:
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }

        switch setting.asValue(themeMode: themeMode) {
        case .transparent:
            backgroundColor = nil
            gradientLayer.removeFromSuperlayer()
        case .solidColor(let color):
            backgroundColor = color
            gradientLayer.removeFromSuperlayer()
        case .gradient(let color1, let color2, let angleRadians):
            backgroundColor = nil

            if gradientLayer.superlayer != self.layer {
                gradientLayer.removeFromSuperlayer()
                layer.addSublayer(gradientLayer)
            }

            /* The start and end points of the gradient when drawn into the layer's
             * coordinate space. The start point corresponds to the first gradient
             * stop, the end point to the last gradient stop. Both points are
             * defined in a unit coordinate space that is then mapped to the
             * layer's bounds rectangle when drawn. (I.e. [0,0] is the bottom-left
             * corner of the layer, [1,1] is the top-right corner.) The default values
             * are [.5,0] and [.5,1] respectively. Both are animatable. */
            let unitCenter = CGPoint(x: 0.5, y: 0.5)
            // Note the signs.
            let startVector = CGPoint(x: +sin(angleRadians), y: -cos(angleRadians))
            let startScale: CGFloat
            switch shapeMode {
            case .circle:
                // In circle mode, we want the startPoint and endPoint to reside
                // on the circumference of the circle.
                startScale = 0.5
            case .rectangle:
                // In rectangle mode, we want the startPoint and endPoint to reside
                // on the edge of the unit square, and thus edge of the rectangle.
                // We therefore scale such that longer axis is a half unit.
                let startSquareScale: CGFloat = max(abs(startVector.x), abs(startVector.y))
                startScale = 0.5 / startSquareScale
            }
            let startPointUL = unitCenter + startVector * +startScale
            // The endpoint should be "opposite" the start point, on the opposite edge of the view.
            let endPointUL = unitCenter + startVector * -startScale

            // UIKit/UIView uses an upper-left origin.
            // Core Graphics/CALayer uses a lower-left origin.
            func convertToLayerUnit(_ point: CGPoint) -> CGPoint {
                // TODO: The documentation clearly indicates that
                // CAGradientLayer.startPoint and endPoint use the layer's
                // coordinate space with lower-left origin.  But the
                // observed behavior is that they use an upper-left origin.
                // I can't figure out why.
                //
                // return CGPoint(x: point.x, y: (1 - point.y))
                return point
            }
            let startPointLL = convertToLayerUnit(startPointUL)
            let endPointLL = convertToLayerUnit(endPointUL)

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            gradientLayer.frame = self.bounds

            gradientLayer.startPoint = startPointLL
            gradientLayer.endPoint = endPointLL

            gradientLayer.colors = [
                color1.cgColor,
                color2.cgColor
            ]

            CATransaction.commit()
        }
    }
}
