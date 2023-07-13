//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// A generator producing styled QR codes for username links.
///
/// The QR codes have a configurable foreground and background, and contain
/// aesthetic features such as an overlaid Signal logo and rounded "pixels".
/// They are scaled up so as to appropriately render the rounded shapes.
class UsernameLinkQRCodeGenerator: QRCodeGenerator {
    /// For the following constants:
    /// - "Point" refers to a coordinate ("pixel") in the QR code.
    /// - "Pixel" refers to a pixel in the image returned by the generator.
    private enum Constants {
        /// The number of pixels used to draw each QR code point.
        static let imagePixelsPerQRCodePoint: Int = 30

        /// The desired percentage of QR code points that should be occluded by
        /// the deadzone. Note that the deadzone size will be calculated in
        /// points (rounded down), as it sits in the context of the QR code
        /// image.
        static let deadzoneSizePointsPercentage: CGFloat = 64 / 184

        /// A number of points by which to pad the deadzone around the drawn
        /// circle.
        static let deadzonePaddingPoints: Int = 1

        /// The percentage of the deadzone to be dedicated to the circle stroke.
        static let deadzoneCircleStrokePercentage: CGFloat = 4 / 64

        /// The percentage of the deadzone in each dimension that will be
        /// occupied by the logo. Note that this will be exact, as inside the
        /// deadzone we do not need to use points.
        static let deadzoneLogoSizePercentage: CGFloat = 38 / 64
    }

    private let foregroundColor: UIColor
    private let backgroundColor: UIColor

    init(foregroundColor: UIColor, backgroundColor: UIColor) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    func generateQRCode(data: Data) -> UIImage? {
        guard let unstyledQRCode = generateQRCode(
            data: data,
            foregroundColor: .black,
            backgroundColor: .clear,
            imageScale: nil
        ) else {
            return nil
        }

        guard
            let cgQRCode = unstyledQRCode.cgImage,
            let qrCodeBitmap = Bitmaps.Image(cgImage: cgQRCode)
        else {
            owsFailDebug("Failed to get bitmap!")
            return unstyledQRCode
        }

        // Specify a centered deadzone in the QR code.
        let deadzone: Bitmaps.Rect = qrCodeBitmap.centeredDeadzone(
            dimensionPercentage: Constants.deadzoneSizePointsPercentage,
            paddingPoints: Constants.deadzonePaddingPoints
        )

        // Make a grid drawing of the QR code.
        let qrCodeGridDrawing = qrCodeBitmap.gridDrawingByMergingAdjacentPixels(
            deadzone: deadzone
        )

        // Paint the grid drawing into a CGContext.
        let styledQRCodeContext: CGContext = .drawing(
            gridDrawing: qrCodeGridDrawing,
            scaledBy: Constants.imagePixelsPerQRCodePoint,
            foregroundColor: foregroundColor.cgColor,
            backgroundColor: backgroundColor.cgColor
        )

        // Draw a circle into the deadzone, inside the padding. When drawing,
        // inset by half the stroke so the circle draws entirely inside the rect
        // instead of straddling the edges (the CoreGraphics behavior).
        let circleRect = deadzone.cgRect(
            scaledBy: CGFloat(Constants.imagePixelsPerQRCodePoint),
            insetBy: CGFloat(Constants.deadzonePaddingPoints)
        )
        let circleStroke = circleRect.width * Constants.deadzoneCircleStrokePercentage
        styledQRCodeContext.setLineWidth(circleStroke)
        styledQRCodeContext.strokeEllipse(in: circleRect.insetBy(
            dx: circleStroke / 2,
            dy: circleStroke / 2
        ))

        // Draw the logo inside the circle in the deadzone.
        let logo = UIImage(named: "signal-logo-40")!.asTintedImage(color: foregroundColor)!
        let logoRect = circleRect.scaled(toPercentage: Constants.deadzoneLogoSizePercentage)
        styledQRCodeContext.draw(logo.cgImage!, in: logoRect)

        guard let styledQRCodeImage = styledQRCodeContext.makeImage() else {
            owsFailDebug("Failed to make styled image!")
            return unstyledQRCode
        }

        return UIImage(cgImage: styledQRCodeImage)
    }
}

extension Bitmaps.Image {
    /// Compute a zone occupying the center of the image, with dimensions
    /// the given percentage of each dimension of the image (rounded down), plus
    /// the given padding on each side.
    func centeredDeadzone(
        dimensionPercentage percentage: CGFloat,
        paddingPoints: Int
    ) -> Bitmaps.Rect {
        owsAssert(
            percentage < 0.5, // Roughly the dimension percentage for deadzoning 30% of the surface area
            "Deadzoning too much of a QR code means it might not scan!"
        )

        let widthRange = centeredRange(
            percentage: percentage,
            ofInt: width,
            padding: paddingPoints
        )
        let heightRange = centeredRange(
            percentage: percentage,
            ofInt: height,
            padding: paddingPoints
        )

        return Bitmaps.Rect(
            x: widthRange.lowerBound,
            y: heightRange.lowerBound,
            width: widthRange.upperBound - widthRange.lowerBound,
            height: heightRange.upperBound - heightRange.lowerBound
        )
    }

    private func centeredRange(
        percentage: CGFloat,
        ofInt int: Int,
        padding: Int
    ) -> ClosedRange<Int> {
        var rangeLength = Int(CGFloat(int) * percentage) + padding * 2
        var remainder = int - rangeLength

        // Ensure we have an even remainder so we can split it evenly.
        if remainder % 2 == 1 {
            rangeLength += 1
            remainder -= 1
        }

        let rangeStart = remainder / 2

        return rangeStart...(rangeStart + rangeLength)
    }
}

private extension CGRect {
    func scaled(toPercentage percentage: CGFloat) -> CGRect {
        let dx = size.width * (1 - percentage) / 2
        let dy = size.height * (1 - percentage) / 2

        return insetBy(dx: dx, dy: dy)
    }
}
