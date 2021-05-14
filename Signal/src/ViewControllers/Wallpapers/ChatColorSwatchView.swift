//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// A round "swatch" that offers a preview of a conversation color option.
public class ChatColorSwatchView: ManualLayoutViewWithLayer {
    public var chatColorValue: ChatColorValue {
        didSet {
            if chatColorValue != oldValue {
                configure()
            }
        }
    }

    public enum Mode {
        case circle
        case rectangle
    }
    private let mode: Mode

    private let gradientLayer = CAGradientLayer()

    public init(chatColorValue: ChatColorValue, mode: Mode) {
        self.chatColorValue = chatColorValue
        self.mode = mode

        super.init(name: "ChatColorSwatchView")

        self.shouldDeactivateConstraints = false

        configure()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)

        addLayoutBlock { view in
            guard let view = view as? ChatColorSwatchView else { return }
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
        let appearance: ChatColorAppearance
    }
    private var state: State?

    private func configure() {
        let size = bounds.size
        let appearance = chatColorValue.appearance
        let newState = State(size: size, appearance: appearance)
        // Exit early if the appearance and bounds haven't changed.
        guard state != newState else {
            return
        }
        self.state = newState

        switch mode {
        case .circle:
            self.layer.cornerRadius = size.smallerAxis * 0.5
            self.clipsToBounds = true
        case .rectangle:
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch appearance {
        case .solidColor(let color):
            backgroundColor = color.asUIColor
            gradientLayer.removeFromSuperlayer()
        case .gradient(let color1, let color2, let angleRadians):
            backgroundColor = nil
            gradientLayer.colors = [
                color1.asUIColor.cgColor,
                color2.asUIColor.cgColor
            ]
            /* The start and end points of the gradient when drawn into the layer's
             * coordinate space. The start point corresponds to the first gradient
             * stop, the end point to the last gradient stop. Both points are
             * defined in a unit coordinate space that is then mapped to the
             * layer's bounds rectangle when drawn. (I.e. [0,0] is the bottom-left
             * corner of the layer, [1,1] is the top-right corner.) The default values
             * are [.5,0] and [.5,1] respectively. Both are animatable. */
            let unitCenter = CGPoint(x: 0.5, y: 0.5)
            let startVector = CGPoint(x: +sin(angleRadians), y: +cos(angleRadians))
            let startScale: CGFloat
            switch mode {
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
            // UIKit uses an upper-left origin.
            // Core Graphics uses a lower-left origin.
            func convertToCoreGraphicsUnit(point: CGPoint) -> CGPoint {
                CGPoint(x: point.x.clamp01(), y: (1 - point.y).clamp01())
            }
            gradientLayer.startPoint = convertToCoreGraphicsUnit(point: unitCenter + startVector * +startScale)
            // The endpoint should be "opposite" the start point, on the opposite edge of the view.
            gradientLayer.endPoint = convertToCoreGraphicsUnit(point: unitCenter + startVector * -startScale)

            if gradientLayer.superlayer != self.layer {
                gradientLayer.removeFromSuperlayer()
                layer.addSublayer(gradientLayer)
            }

            gradientLayer.frame = self.bounds
        }

        CATransaction.commit()
    }
}
