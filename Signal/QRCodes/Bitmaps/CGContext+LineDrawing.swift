//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics

extension CGContext {
    /// Returns a context painted with the given grid drawing, scaled by the
    /// given amount.
    ///
    /// The origin of the context is the bottom-left, matching the default
    /// behavior for CoreGraphics contexts.
    ///
    /// Properties such as the line width, join, cap, color will be set on the
    /// context.
    ///
    /// - Parameter scaledBy
    /// Represents how many painted pixels should be used to represent a single
    /// "pixel" in the grid drawing. Higher scale translates to smoother curves
    /// at high resolution.
    static func drawing(
        gridDrawing drawing: Bitmaps.GridDrawing,
        scaledBy scaleInt: Int,
        lineJoin: CGLineJoin = .round,
        lineCap: CGLineCap = .round,
        foregroundColor: CGColor,
        backgroundColor: CGColor
    ) -> CGContext {
        let scaleFloat = CGFloat(scaleInt)

        let cgContext = CGContext(
            data: nil,
            width: drawing.width * scaleInt,
            height: drawing.height * scaleInt,
            bitsPerComponent: 8,
            bytesPerRow: 4 * drawing.width * scaleInt, // Four components per pixel
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        cgContext.setFillColor(backgroundColor)
        cgContext.fill([cgContext.boundingRect])

        cgContext.setLineWidth(scaleFloat)
        cgContext.setLineJoin(lineJoin)
        cgContext.setLineCap(lineCap)
        cgContext.setStrokeColor(foregroundColor)

        let segmentsCGPointPairs = drawing.segments.flatMap { segment -> [CGPoint] in
            return [
                segment.start.cgPoint(scaledBy: scaleFloat),
                segment.end.cgPoint(scaledBy: scaleFloat)
            ]
        }

        cgContext.strokeLineSegments(between: segmentsCGPointPairs)

        return cgContext
    }

    private var boundingRect: CGRect {
        return CGRect(origin: .zero, size: CGSize(width: width, height: height))
    }
}
