//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
import UIKit

@testable import Signal
@testable import SignalUI

struct CVWallpaperBlurViewTest {

    // MARK: - Average color

    private func rgba(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func makeImage(size: CGSize, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    @Test
    func testAverageColorOfSolidImageIsThatColor() throws {
        let image = makeImage(size: CGSize(width: 40, height: 40)) { context in
            context.setFillColor(UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }

        let color = try #require(image.averageColor())
        let (r, g, b, a) = rgba(color)

        #expect(abs(r - 0.2) < 0.02)
        #expect(abs(g - 0.4) < 0.02)
        #expect(abs(b - 0.6) < 0.02)
        #expect(abs(a - 1) < 0.01)
    }

    @Test
    func testAverageColorOfHalfBlackHalfWhiteImageIsMidGray() throws {
        let image = makeImage(size: CGSize(width: 40, height: 40)) { context in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }

        let color = try #require(image.averageColor())
        let (r, g, b, _) = rgba(color)

        #expect(abs(r - 0.5) < 0.05)
        #expect(abs(g - 0.5) < 0.05)
        #expect(abs(b - 0.5) < 0.05)
    }

    // MARK: - Fallback background

    @Test
    func testBubbleFullyCoveredByImageNeedsNoFallback() {
        let bubbleBounds = CGRect(x: 0, y: 0, width: 326, height: 372)
        let imageFrame = CGRect(x: -16, y: -351, width: 402, height: 874)

        #expect(!CVWallpaperBlurView.needsFallbackBackground(bubbleBounds: bubbleBounds, imageFrame: imageFrame))
    }

    @Test
    func testBubbleExactlyMatchingImageNeedsNoFallback() {
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)

        #expect(!CVWallpaperBlurView.needsFallbackBackground(bubbleBounds: frame, imageFrame: frame))
    }

    /// A very tall message is taller than the screen-sized wallpaper image, so the
    /// bottom of the bubble has no fill. This is the bug from issue #6356.
    @Test
    func testBubbleTallerThanImageNeedsFallback() {
        let bubbleBounds = CGRect(x: 0, y: 0, width: 326, height: 1820)
        let imageFrame = CGRect(x: -16, y: -351, width: 402, height: 874)

        #expect(CVWallpaperBlurView.needsFallbackBackground(bubbleBounds: bubbleBounds, imageFrame: imageFrame))
    }

    @Test
    func testBubbleStartingAboveImageNeedsFallback() {
        let bubbleBounds = CGRect(x: 0, y: 0, width: 326, height: 372)
        let imageFrame = CGRect(x: -16, y: 100, width: 402, height: 874)

        #expect(CVWallpaperBlurView.needsFallbackBackground(bubbleBounds: bubbleBounds, imageFrame: imageFrame))
    }

    @Test
    func testBubbleWiderThanImageNeedsFallback() {
        let bubbleBounds = CGRect(x: 0, y: 0, width: 326, height: 372)
        let imageFrame = CGRect(x: 0, y: -100, width: 300, height: 874)

        #expect(CVWallpaperBlurView.needsFallbackBackground(bubbleBounds: bubbleBounds, imageFrame: imageFrame))
    }
}
