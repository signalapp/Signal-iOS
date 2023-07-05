//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics

extension Bitmaps {
    struct Point: Hashable, Equatable {
        let x: Int
        let y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        /// Returns the point at the center of the "pixel" at this point in a
        /// scaled context.
        ///
        /// Specifically, for a given point `{X,Y}` and scale `S` returns the
        /// point `{X*S + S/2, Y*S + S/2}`.
        func cgPoint(scaledBy s: CGFloat) -> CGPoint {
            return CGPoint(
                x: CGFloat(x) * s + s / 2,
                y: CGFloat(y) * s + s / 2
            )
        }
    }

    struct Rect: Equatable {
        let origin: Point
        let width: Int
        let height: Int

        init(x: Int, y: Int, width: Int, height: Int) {
            self.origin = Point(x: x, y: y)
            self.width = width
            self.height = height
        }

        /// Whether the rect contains the given point. Points along the leading
        /// edges are contained, but not those along the trailing edges.
        func contains(_ point: Point) -> Bool {
            if
                point.x >= origin.x,
                point.x < (origin.x + width),
                point.y >= origin.y,
                point.y < (origin.y + height)
            {
                return true
            }

            return false
        }

        /// Returns the ``CGRect`` with corners at the centers of the "pixels"
        /// at this rect's corners in a scaled context.
        ///
        /// See ``Point.cgPoint(scaledBy:)`` for more details.
        func cgRect(
            scaledBy scale: CGFloat = 1,
            insetBy inset: CGFloat = 0
        ) -> CGRect {
            let scaledOrigin = origin.cgPoint(scaledBy: scale)

            return CGRect(
                x: scaledOrigin.x + inset * scale,
                y: scaledOrigin.y + inset * scale,
                width: CGFloat(width - 1) * scale - inset * scale * 2,
                height: CGFloat(height - 1) * scale - inset * scale * 2
            )
        }
    }
}
