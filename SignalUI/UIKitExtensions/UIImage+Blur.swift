//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreImage
import SignalServiceKit
import UIKit

public extension UIImage {

    // Name corresponds to CIImage filter.
    enum CompositingMode: String {
        case sourceOver = "CISourceOverCompositing"
        case sourceAtop = "CISourceAtopCompositing"
        case sourceIn = "CISourceInCompositing"
        case sourceOut = "CISourceOutCompositing"
        case multiply = "CIMultiplyCompositing"
        case screen = "CIScreenBlendMode"
        case overlay = "CIOverlayBlendMode"
        case darken = "CIDarkenBlendMode"
        case lighten = "CILightenBlendMode"
        case linearDodge = "CILinearDodgeBlendMode"
    }

    @concurrent
    func withGaussianBlurAsync(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) async throws -> UIImage {
        AssertNotOnMainThread()
        return UIImage(cgImage: try _cgImageWithGaussianBlur(radius: radius, resizeToMaxPixelDimension: resizeToMaxPixelDimension))
    }

    @concurrent
    func cgImageWithGaussianBlurAsync(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) async throws -> CGImage {
        AssertNotOnMainThread()
        return try self._cgImageWithGaussianBlur(radius: radius, resizeToMaxPixelDimension: resizeToMaxPixelDimension)
    }

    private func _cgImageWithGaussianBlur(radius: CGFloat, resizeToMaxPixelDimension: CGFloat) throws -> CGImage {
        guard let resizedImage = self.resized(maxDimensionPixels: resizeToMaxPixelDimension) else {
            throw OWSAssertionError("Failed to downsize image for blur")
        }
        return try resizedImage._cgImageWithGaussianBlur(radius: radius)
    }

    func withGaussianBlur(radius: CGFloat, tintColor: UIColor? = nil) throws -> UIImage {
        var overlays: [(UIColor, CompositingMode)] = []
        if let tintColor {
            overlays.append((tintColor, .sourceAtop))
        }
        return try withGaussianBlur(radius: radius, colorOverlays: overlays)
    }

    func withGaussianBlur(
        radius: CGFloat,
        colorOverlays overlays: [(UIColor, CompositingMode)] = [],
        vibrancy: CGFloat = 0,
        exposureAdjustment: CGFloat = 0,
    ) throws -> UIImage {
        return UIImage(
            cgImage: try _cgImageWithGaussianBlur(
                radius: radius,
                colorOverlays: overlays,
                vibrancy: vibrancy,
                exposureAdjustment: exposureAdjustment,
            ),
        )
    }

    private func _cgImageWithGaussianBlur(
        radius: CGFloat,
        colorOverlays overlays: [(UIColor, CompositingMode)] = [],
        vibrancy: CGFloat = 0,
        exposureAdjustment: CGFloat = 0,
    ) throws -> CGImage {

        guard let cgImage else {
            throw OWSAssertionError("Missing cgImage.")
        }

        let inputImage = CIImage(cgImage: cgImage)

        // 1. In order to get a nice edge-to-edge blur, we must apply a clamp filter and *then* the blur filter.
        guard
            let clampFilter = CIFilter(
                name: "CIAffineClamp",
                parameters: [
                    kCIInputImageKey: inputImage,
                ],
            )
        else {
            throw OWSAssertionError("Failed to create CIAffineClamp filter.")
        }
        clampFilter.setDefaults()
        guard let clampOutput = clampFilter.outputImage else {
            throw OWSAssertionError("Failed to clamp image.")
        }

        // 2. Create blurred image.
        guard
            let blurFilter = CIFilter(
                name: "CIGaussianBlur",
                parameters: [
                    kCIInputRadiusKey: radius,
                    kCIInputImageKey: clampOutput,
                ],
            )
        else {
            throw OWSAssertionError("Failed to create CIGaussianBlur filter.")
        }
        guard let blurredOutput = blurFilter.outputImage else {
            throw OWSAssertionError("Failed to create blurred image.")
        }

        // 3. Apply overlays.
        var outputImage: CIImage = blurredOutput
        for (overlayColor, compositingMode) in overlays {
            guard
                let overlayFilter = CIFilter(
                    name: "CIConstantColorGenerator",
                    parameters: [
                        kCIInputColorKey: CIColor(color: overlayColor),
                    ],
                )
            else {
                throw OWSAssertionError("Could not create CIConstantColorGenerator.")
            }
            guard let overlayImage = overlayFilter.outputImage else {
                throw OWSAssertionError("Could not create overlayImage.")
            }

            guard
                let compositingFilter = CIFilter(
                    name: compositingMode.rawValue,
                    parameters: [
                        kCIInputBackgroundImageKey: outputImage,
                        kCIInputImageKey: overlayImage,
                    ],
                )
            else {
                throw OWSAssertionError("Could not create \(compositingMode.rawValue).")
            }
            guard let tintedImage = compositingFilter.outputImage else {
                throw OWSAssertionError("Could not create tintedImage.")
            }
            outputImage = tintedImage
        }

        // 4. Vibrance.
        if
            vibrancy != 0,
            let vibranceFilter = CIFilter(
                name: "CIVibrance",
                parameters: [
                    kCIInputImageKey: outputImage,
                    kCIInputAmountKey: vibrancy,
                ],
            )
        {
            guard let vibrantImage = vibranceFilter.outputImage else {
                throw OWSAssertionError("Could not create vibrantImage.")
            }
            outputImage = vibrantImage
        }

        // 5. Exposure adjust.

        if
            exposureAdjustment != 0,
            let exposureAdjustFilter = CIFilter(
                name: "CIExposureAdjust",
                parameters: [
                    kCIInputImageKey: outputImage,
                    kCIInputEVKey: exposureAdjustment,
                ],
            )
        {
            guard let exposureAdjustedImage = exposureAdjustFilter.outputImage else {
                throw OWSAssertionError("Could not create exposureAdjustedImage.")
            }
            outputImage = exposureAdjustedImage
        }

        // 6. Convert to CGImage.
        let context = CIContext(options: nil)
        guard let result = context.createCGImage(outputImage, from: inputImage.extent) else {
            throw OWSAssertionError("Failed to create CGImage from blurred output")
        }

        return result
    }
}
