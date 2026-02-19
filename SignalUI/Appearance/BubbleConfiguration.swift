//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

///
/// An object that describes shape of a bubble in chat.
///
/// This structure is designed to work in conjunction with `CVColorOrGradientView` and `CVWallpaperBlurView`.
///
public struct BubbleConfiguration {

    /// Bubble's corner rounding configuration.
    public let corners: Corners

    /// Bubble's stroke configuration.
    ///
    /// This property can be `nil` for no stroke.
    public let stroke: Stroke?

    /// - Parameter corners: Bubble's corner rouding configuration.
    /// - Parameter stroke: Bubble's stroke configuration. Pass `nil` for no stroke.
    public init(corners: Corners, stroke: Stroke? = nil) {
        self.stroke = stroke
        self.corners = corners
    }

    // MARK: - Corners

    ///
    /// An object that contains configuration of chat bubble corner rounding..
    ///
    public struct Corners {

        fileprivate enum Style {
            /// Same radius for all corners.
            case uniform(radius: CGFloat)
            /// One radius for corners in `sharpCorners`, other radius for the rest.
            case segmented(sharpCorners: UIRectCorner, sharpCornerRadius: CGFloat, wideCornerRadius: CGFloat)
            /// Dynamic corner radius dependent on view's size.
            case capsule(maxRadius: CGFloat)
        }

        fileprivate let style: Style

        /// Creates a configuration where all corners have the same radius.
        public static func uniform(_ radius: CGFloat) -> Corners {
            Corners(style: .uniform(radius: radius))
        }

        /// Creates a configuration where some corners have one (sharp) corner radius
        /// and the rest have another (wide) corner radius.
        ///
        /// - Parameter sharpCorners: Set of corners that should have `sharpCornerRadius`.
        /// - Parameter sharpCornerRadius: Radius for corners specified in `sharpCorners`.
        /// - Parameter wideCornerRadius: Radius to use in corners that are not in `sharpCorners`.
        ///
        /// This method will check parameter value and will fall back to `uniform()` if needed.
        public static func segmented(
            sharpCorners: OWSDirectionalRectCorner,
            sharpCornerRadius: CGFloat,
            wideCornerRadius: CGFloat,
        ) -> Corners {
            if sharpCornerRadius == wideCornerRadius {
                return .uniform(sharpCornerRadius)
            }
            if sharpCorners.isEmpty {
                return .uniform(wideCornerRadius)
            }
            if sharpCorners == [.allCorners] {
                return .uniform(sharpCornerRadius)
            }
            return Corners(style: .segmented(
                sharpCorners: UIView.uiRectCorner(forOWSDirectionalRectCorner: sharpCorners),
                sharpCornerRadius: sharpCornerRadius,
                wideCornerRadius: wideCornerRadius,
            ))
        }

        /// Creates a configuration where corner radius is calculated dynamically based on view's dimensions.
        ///
        /// - Parameter maxRadius: Upper limit for corner radius. Pass `0` for no limit.
        public static func capsule(maxRadius: CGFloat = 0) -> Corners {
            Corners(style: .capsule(maxRadius: maxRadius))
        }

        /// Does a quick check if corner configuration has uniform corners and returns corner radius if it does.
        ///
        /// - Returns Corner radius if corners are uniform, otherwise returns `nil`.
        ///
        /// It more performant to set `CALayer.cornerRadius` instead of doing a mask layer.
        /// This method is design to help with that.
        public func uniformCornerRadius(for rect: CGRect) -> CGFloat? {
            if case .segmented = style {
                return nil
            }
            return radius(for: .topLeft, in: rect)
        }

        /// - Returns Radius for a specific corner for a given view rectangle.
        public func radius(for corner: UIRectCorner, in rect: CGRect) -> CGFloat {
            switch style {
            case .uniform(let radius):
                return min(radius, rect.size.smallerAxis / 2)

            case .segmented(let sharpCorners, let sharpCornerRadius, let wideCornerRadius):
                return sharpCorners.contains(corner) ? sharpCornerRadius : wideCornerRadius

            case .capsule(let maxRadius):
                let radius = rect.size.smallerAxis / 2
                return maxRadius > 0 ? min(maxRadius, radius) : radius
            }
        }
    }

    // MARK: - Stroke

    ///
    /// An object that contains description of chat bubble's outline (stroke).
    ///
    public struct Stroke {

        /// Stroke's color.
        public let color: UIColor

        /// Stroke width.
        ///
        /// Note that center of the stroke line lies on the edge of the bubble view.
        /// Therefore half of the width provided will be drawn inside of the view and another half - outside.
        public let width: CGFloat

        public init(color: UIColor, width: CGFloat) {
            self.color = color
            self.width = width
        }
    }

    // MARK: UIBezierPath conversions

    /// - Returns `UIBezierPath` describing bubble shape.
    ///
    /// Designed to allow callers to configure masking layers that match bubble shape..
    public func bubblePath(for rect: CGRect) -> UIBezierPath {
        switch corners.style {
        case .uniform:
            let cornerRadius = corners.radius(for: .topLeft, in: rect)
            return UIBezierPath(cgPath: CGPath(
                roundedRect: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil,
            ))

        case .segmented(let sharpCorners, let sharpCornerRadius, let wideCornerRadius):
            return UIBezierPath.roundedRect(
                rect,
                sharpCorners: sharpCorners,
                sharpCornerRadius: sharpCornerRadius,
                wideCornerRadius: wideCornerRadius,
            )

        case .capsule:
            let cornerRadius = corners.radius(for: .topLeft, in: rect)
            return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        }
    }

    /// - Returns `UIBezierPath` containing stroke path for the provided `UIRect`.
    /// Will return `nil` if `BubbleConfiguration` doesn't have stroke specified.
    ///
    /// Designed to work with `CAShapeLayer` to add stroke to chat bubbles.
    public func strokePath(for rect: CGRect) -> UIBezierPath? {
        guard stroke != nil else { return nil }

        return bubblePath(for: rect)
    }
}
