//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol QRCodeGenerator {
    /// Generate a QR code encoding the given data.
    /// - Returns
    /// An image containing the QR code, or `nil` if there was an error.
    func generateQRCode(data: Data) -> UIImage?
}

extension QRCodeGenerator {
    func generateQRCode(url: URL) -> UIImage? {
        guard let urlData: Data = url.absoluteString.data(using: .utf8) else {
            owsFailDebug("Failed to convert URL to data!")
            return nil
        }

        return generateQRCode(data: urlData)
    }

    /// Generate a QR code image encoding the given data.
    ///
    /// - Parameter data
    /// The data to be encoded into the QR code.
    /// - Parameter foregroundColor
    /// The foreground color of the QR code image.
    /// - Parameter backgrounColor
    /// The background color of the QR code image.
    /// - Parameter imageScale
    /// An amount by which to scale the pixels of the QR code image. For
    /// example, passing 10 scales each individual pixel to a 10x10 block of
    /// pixels. A value of `nil` indicates the image should be unscaled.
    func generateQRCode(
        data: Data,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        imageScale: UInt?
    ) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            owsFailDebug("Failed to get QR code generation filer!")
            return nil
        }

        filter.setValue("H", forKey: "inputCorrectionLevel")
        filter.setValue(data, forKey: "inputMessage")

        guard let ciImage = filter.outputImage else {
            owsFailDebug("Failed to get CI image!")
            return nil
        }

        // Change the color using CIFilter
        let colorParameters = [
            "inputColor0": CIColor(color: foregroundColor),
            "inputColor1": CIColor(color: backgroundColor)
        ]

        let recoloredCIImage = ciImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        let scaledCIImage: CIImage = {
            if let imageScale {
                return recoloredCIImage.transformed(by: CGAffineTransform.scale(CGFloat(imageScale)))
            }

            return recoloredCIImage
        }()

        // UIImages backed by a CIImage won't render without antialiasing, so we convert the backing
        // image to a CGImage, which can be scaled crisply.
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else {
            owsFailDebug("Failed to create CG image!")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
