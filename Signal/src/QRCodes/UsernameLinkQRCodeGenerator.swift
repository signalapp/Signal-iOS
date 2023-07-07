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
/// They are significantly scaled up so as to appropriately render the rounded
/// shapes.
class UsernameLinkQRCodeGenerator: QRCodeGenerator {
    private enum Constants {
        static let imageScale: Int = 30
        static let deadzonePercentage: CGFloat = 1/3
        static let deadzoneCircleInset: CGFloat = 0.75
        static let deadzoneLogoInset: CGFloat = 2.5
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
            return nil
        }

        // Specify a centered deadzone in the QR code.
        let deadzone = qrCodeBitmap.centeredDeadzone(
            dimensionPercentage: Constants.deadzonePercentage
        )

        // Make a grid drawing of the QR code.
        let qrCodeGridDrawing = qrCodeBitmap.gridDrawingByMergingAdjacentPixels(
            deadzone: deadzone
        )

        // Paint the grid drawing into a CGContext.
        let styledQRCodeContext: CGContext = .drawing(
            gridDrawing: qrCodeGridDrawing,
            scaledBy: Constants.imageScale,
            foregroundColor: foregroundColor.cgColor,
            backgroundColor: backgroundColor.cgColor
        )

        // Draw a circle in the deadzone.
        let circleRect = deadzone.cgRect(
            scaledBy: CGFloat(Constants.imageScale),
            insetBy: Constants.deadzoneCircleInset
        )
        styledQRCodeContext.strokeEllipse(in: circleRect)

        // Draw the logo inside the circle in the deadzone.
        let logo = UIImage(named: "signal-logo-40")!
            .asTintedImage(color: foregroundColor)!
            .cgImage!
        let logoRect = deadzone.cgRect(
            scaledBy: CGFloat(Constants.imageScale),
            insetBy: Constants.deadzoneLogoInset
        )
        styledQRCodeContext.draw(logo, in: logoRect)

        guard let styledQRCodeImage = styledQRCodeContext.makeImage() else {
            owsFailDebug("Failed to make styled image!")
            return nil
        }

        return UIImage(cgImage: styledQRCodeImage)
    }
}

extension Bitmaps.Image {
    /// Compute a zone occupying the center of the image, with dimensions
    /// roughly the given percentage of each dimension of the image.
    func centeredDeadzone(dimensionPercentage percentage: CGFloat) -> Bitmaps.Rect {
        owsAssert(
            percentage < 0.5, // Roughly the dimension percentage for deadzoning 30% of the surface area
            "Deadzoning too much of a QR code means it might not scan!"
        )

        let widthRange = centeredRange(percentage: percentage, ofInt: width)
        let heightRange = centeredRange(percentage: percentage, ofInt: height)

        return Bitmaps.Rect(
            x: widthRange.lowerBound,
            y: heightRange.lowerBound,
            width: widthRange.upperBound - widthRange.lowerBound,
            height: heightRange.upperBound - heightRange.lowerBound
        )
    }

    private func centeredRange(percentage: CGFloat, ofInt int: Int) -> ClosedRange<Int> {
        var rangeLength = Int(CGFloat(int) * percentage)
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
