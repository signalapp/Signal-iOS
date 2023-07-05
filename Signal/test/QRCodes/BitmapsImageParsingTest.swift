//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

/// Do bitmap images parse correctly from other images?
class BitmapsImageParsingTest: XCTestCase {
    func testKnownQRCode() {
        let knownQRCodePixels: [(Int, Int, Bool)] = [
            (0, 26, false), (1, 26, false), (2, 26, false), (3, 26, false), (4, 26, false), (5, 26, false), (6, 26, false), (7, 26, false), (8, 26, false), (9, 26, false), (10, 26, false), (11, 26, false), (12, 26, false), (13, 26, false), (14, 26, false), (15, 26, false), (16, 26, false), (17, 26, false), (18, 26, false), (19, 26, false), (20, 26, false), (21, 26, false), (22, 26, false), (23, 26, false), (24, 26, false), (25, 26, false), (26, 26, false),
            (0, 25, false), (1, 25, true), (2, 25, true), (3, 25, true), (4, 25, true), (5, 25, true), (6, 25, true), (7, 25, true), (8, 25, false), (9, 25, true), (10, 25, false), (11, 25, false), (12, 25, false), (13, 25, false), (14, 25, true), (15, 25, true), (16, 25, true), (17, 25, true), (18, 25, false), (19, 25, true), (20, 25, true), (21, 25, true), (22, 25, true), (23, 25, true), (24, 25, true), (25, 25, true), (26, 25, false),
            (0, 24, false), (1, 24, true), (2, 24, false), (3, 24, false), (4, 24, false), (5, 24, false), (6, 24, false), (7, 24, true), (8, 24, false), (9, 24, true), (10, 24, false), (11, 24, false), (12, 24, true), (13, 24, true), (14, 24, false), (15, 24, false), (16, 24, false), (17, 24, false), (18, 24, false), (19, 24, true), (20, 24, false), (21, 24, false), (22, 24, false), (23, 24, false), (24, 24, false), (25, 24, true), (26, 24, false),
            (0, 23, false), (1, 23, true), (2, 23, false), (3, 23, true), (4, 23, true), (5, 23, true), (6, 23, false), (7, 23, true), (8, 23, false), (9, 23, true), (10, 23, true), (11, 23, false), (12, 23, false), (13, 23, true), (14, 23, false), (15, 23, true), (16, 23, false), (17, 23, true), (18, 23, false), (19, 23, true), (20, 23, false), (21, 23, true), (22, 23, true), (23, 23, true), (24, 23, false), (25, 23, true), (26, 23, false),
            (0, 22, false), (1, 22, true), (2, 22, false), (3, 22, true), (4, 22, true), (5, 22, true), (6, 22, false), (7, 22, true), (8, 22, false), (9, 22, true), (10, 22, true), (11, 22, true), (12, 22, false), (13, 22, true), (14, 22, false), (15, 22, false), (16, 22, true), (17, 22, false), (18, 22, false), (19, 22, true), (20, 22, false), (21, 22, true), (22, 22, true), (23, 22, true), (24, 22, false), (25, 22, true), (26, 22, false),
            (0, 21, false), (1, 21, true), (2, 21, false), (3, 21, true), (4, 21, true), (5, 21, true), (6, 21, false), (7, 21, true), (8, 21, false), (9, 21, false), (10, 21, true), (11, 21, true), (12, 21, false), (13, 21, true), (14, 21, false), (15, 21, true), (16, 21, true), (17, 21, true), (18, 21, false), (19, 21, true), (20, 21, false), (21, 21, true), (22, 21, true), (23, 21, true), (24, 21, false), (25, 21, true), (26, 21, false),
            (0, 20, false), (1, 20, true), (2, 20, false), (3, 20, false), (4, 20, false), (5, 20, false), (6, 20, false), (7, 20, true), (8, 20, false), (9, 20, true), (10, 20, true), (11, 20, true), (12, 20, false), (13, 20, false), (14, 20, false), (15, 20, false), (16, 20, false), (17, 20, true), (18, 20, false), (19, 20, true), (20, 20, false), (21, 20, false), (22, 20, false), (23, 20, false), (24, 20, false), (25, 20, true), (26, 20, false),
            (0, 19, false), (1, 19, true), (2, 19, true), (3, 19, true), (4, 19, true), (5, 19, true), (6, 19, true), (7, 19, true), (8, 19, false), (9, 19, true), (10, 19, false), (11, 19, true), (12, 19, false), (13, 19, true), (14, 19, false), (15, 19, true), (16, 19, false), (17, 19, true), (18, 19, false), (19, 19, true), (20, 19, true), (21, 19, true), (22, 19, true), (23, 19, true), (24, 19, true), (25, 19, true), (26, 19, false),
            (0, 18, false), (1, 18, false), (2, 18, false), (3, 18, false), (4, 18, false), (5, 18, false), (6, 18, false), (7, 18, false), (8, 18, false), (9, 18, false), (10, 18, false), (11, 18, true), (12, 18, true), (13, 18, false), (14, 18, true), (15, 18, false), (16, 18, false), (17, 18, false), (18, 18, false), (19, 18, false), (20, 18, false), (21, 18, false), (22, 18, false), (23, 18, false), (24, 18, false), (25, 18, false), (26, 18, false),
            (0, 17, false), (1, 17, true), (2, 17, true), (3, 17, false), (4, 17, false), (5, 17, true), (6, 17, true), (7, 17, true), (8, 17, false), (9, 17, false), (10, 17, false), (11, 17, true), (12, 17, false), (13, 17, true), (14, 17, true), (15, 17, false), (16, 17, true), (17, 17, false), (18, 17, false), (19, 17, false), (20, 17, true), (21, 17, false), (22, 17, true), (23, 17, true), (24, 17, true), (25, 17, true), (26, 17, false),
            (0, 16, false), (1, 16, false), (2, 16, false), (3, 16, false), (4, 16, true), (5, 16, false), (6, 16, true), (7, 16, false), (8, 16, false), (9, 16, false), (10, 16, false), (11, 16, false), (12, 16, false), (13, 16, false), (14, 16, true), (15, 16, true), (16, 16, true), (17, 16, true), (18, 16, false), (19, 16, false), (20, 16, false), (21, 16, true), (22, 16, true), (23, 16, false), (24, 16, true), (25, 16, false), (26, 16, false),
            (0, 15, false), (1, 15, false), (2, 15, true), (3, 15, true), (4, 15, true), (5, 15, true), (6, 15, true), (7, 15, true), (8, 15, true), (9, 15, false), (10, 15, true), (11, 15, true), (12, 15, false), (13, 15, false), (14, 15, false), (15, 15, false), (16, 15, true), (17, 15, true), (18, 15, true), (19, 15, true), (20, 15, true), (21, 15, true), (22, 15, true), (23, 15, true), (24, 15, false), (25, 15, false), (26, 15, false),
            (0, 14, false), (1, 14, true), (2, 14, false), (3, 14, false), (4, 14, true), (5, 14, false), (6, 14, false), (7, 14, false), (8, 14, false), (9, 14, false), (10, 14, true), (11, 14, false), (12, 14, false), (13, 14, true), (14, 14, false), (15, 14, true), (16, 14, false), (17, 14, false), (18, 14, false), (19, 14, false), (20, 14, false), (21, 14, false), (22, 14, false), (23, 14, true), (24, 14, true), (25, 14, false), (26, 14, false),
            (0, 13, false), (1, 13, false), (2, 13, true), (3, 13, false), (4, 13, true), (5, 13, false), (6, 13, false), (7, 13, true), (8, 13, true), (9, 13, true), (10, 13, false), (11, 13, false), (12, 13, true), (13, 13, false), (14, 13, true), (15, 13, true), (16, 13, true), (17, 13, false), (18, 13, true), (19, 13, true), (20, 13, false), (21, 13, false), (22, 13, true), (23, 13, true), (24, 13, true), (25, 13, true), (26, 13, false),
            (0, 12, false), (1, 12, true), (2, 12, false), (3, 12, false), (4, 12, true), (5, 12, true), (6, 12, false), (7, 12, false), (8, 12, true), (9, 12, false), (10, 12, true), (11, 12, true), (12, 12, false), (13, 12, true), (14, 12, false), (15, 12, false), (16, 12, true), (17, 12, false), (18, 12, false), (19, 12, false), (20, 12, false), (21, 12, true), (22, 12, false), (23, 12, false), (24, 12, true), (25, 12, false), (26, 12, false),
            (0, 11, false), (1, 11, false), (2, 11, false), (3, 11, false), (4, 11, false), (5, 11, true), (6, 11, true), (7, 11, true), (8, 11, false), (9, 11, false), (10, 11, true), (11, 11, false), (12, 11, true), (13, 11, true), (14, 11, true), (15, 11, true), (16, 11, true), (17, 11, true), (18, 11, false), (19, 11, false), (20, 11, true), (21, 11, true), (22, 11, true), (23, 11, true), (24, 11, false), (25, 11, false), (26, 11, false),
            (0, 10, false), (1, 10, false), (2, 10, false), (3, 10, true), (4, 10, true), (5, 10, true), (6, 10, false), (7, 10, false), (8, 10, false), (9, 10, false), (10, 10, true), (11, 10, false), (12, 10, true), (13, 10, false), (14, 10, true), (15, 10, false), (16, 10, true), (17, 10, false), (18, 10, false), (19, 10, true), (20, 10, true), (21, 10, true), (22, 10, false), (23, 10, true), (24, 10, true), (25, 10, false), (26, 10, false),
            (0, 9, false), (1, 9, true), (2, 9, true), (3, 9, false), (4, 9, false), (5, 9, true), (6, 9, true), (7, 9, true), (8, 9, false), (9, 9, false), (10, 9, true), (11, 9, true), (12, 9, false), (13, 9, true), (14, 9, true), (15, 9, false), (16, 9, true), (17, 9, true), (18, 9, true), (19, 9, true), (20, 9, true), (21, 9, true), (22, 9, true), (23, 9, true), (24, 9, false), (25, 9, false), (26, 9, false),
            (0, 8, false), (1, 8, false), (2, 8, false), (3, 8, false), (4, 8, false), (5, 8, false), (6, 8, false), (7, 8, false), (8, 8, false), (9, 8, true), (10, 8, false), (11, 8, true), (12, 8, false), (13, 8, false), (14, 8, true), (15, 8, true), (16, 8, false), (17, 8, true), (18, 8, false), (19, 8, false), (20, 8, false), (21, 8, true), (22, 8, false), (23, 8, false), (24, 8, false), (25, 8, false), (26, 8, false),
            (0, 7, false), (1, 7, true), (2, 7, true), (3, 7, true), (4, 7, true), (5, 7, true), (6, 7, true), (7, 7, true), (8, 7, false), (9, 7, false), (10, 7, false), (11, 7, false), (12, 7, false), (13, 7, false), (14, 7, false), (15, 7, false), (16, 7, false), (17, 7, true), (18, 7, false), (19, 7, true), (20, 7, false), (21, 7, true), (22, 7, false), (23, 7, false), (24, 7, false), (25, 7, false), (26, 7, false),
            (0, 6, false), (1, 6, true), (2, 6, false), (3, 6, false), (4, 6, false), (5, 6, false), (6, 6, false), (7, 6, true), (8, 6, false), (9, 6, true), (10, 6, false), (11, 6, true), (12, 6, false), (13, 6, true), (14, 6, false), (15, 6, true), (16, 6, false), (17, 6, true), (18, 6, false), (19, 6, false), (20, 6, false), (21, 6, true), (22, 6, true), (23, 6, true), (24, 6, true), (25, 6, true), (26, 6, false),
            (0, 5, false), (1, 5, true), (2, 5, false), (3, 5, true), (4, 5, true), (5, 5, true), (6, 5, false), (7, 5, true), (8, 5, false), (9, 5, true), (10, 5, false), (11, 5, true), (12, 5, true), (13, 5, false), (14, 5, true), (15, 5, true), (16, 5, false), (17, 5, true), (18, 5, true), (19, 5, true), (20, 5, true), (21, 5, true), (22, 5, true), (23, 5, true), (24, 5, false), (25, 5, true), (26, 5, false),
            (0, 4, false), (1, 4, true), (2, 4, false), (3, 4, true), (4, 4, true), (5, 4, true), (6, 4, false), (7, 4, true), (8, 4, false), (9, 4, false), (10, 4, false), (11, 4, true), (12, 4, false), (13, 4, true), (14, 4, false), (15, 4, false), (16, 4, true), (17, 4, false), (18, 4, true), (19, 4, true), (20, 4, true), (21, 4, false), (22, 4, false), (23, 4, true), (24, 4, true), (25, 4, true), (26, 4, false),
            (0, 3, false), (1, 3, true), (2, 3, false), (3, 3, true), (4, 3, true), (5, 3, true), (6, 3, false), (7, 3, true), (8, 3, false), (9, 3, false), (10, 3, false), (11, 3, false), (12, 3, true), (13, 3, true), (14, 3, true), (15, 3, true), (16, 3, true), (17, 3, true), (18, 3, true), (19, 3, true), (20, 3, false), (21, 3, false), (22, 3, true), (23, 3, false), (24, 3, true), (25, 3, false), (26, 3, false),
            (0, 2, false), (1, 2, true), (2, 2, false), (3, 2, false), (4, 2, false), (5, 2, false), (6, 2, false), (7, 2, true), (8, 2, false), (9, 2, true), (10, 2, true), (11, 2, true), (12, 2, true), (13, 2, false), (14, 2, true), (15, 2, false), (16, 2, true), (17, 2, false), (18, 2, false), (19, 2, true), (20, 2, true), (21, 2, true), (22, 2, true), (23, 2, true), (24, 2, true), (25, 2, false), (26, 2, false),
            (0, 1, false), (1, 1, true), (2, 1, true), (3, 1, true), (4, 1, true), (5, 1, true), (6, 1, true), (7, 1, true), (8, 1, false), (9, 1, true), (10, 1, false), (11, 1, false), (12, 1, false), (13, 1, true), (14, 1, true), (15, 1, false), (16, 1, true), (17, 1, false), (18, 1, false), (19, 1, false), (20, 1, false), (21, 1, false), (22, 1, false), (23, 1, true), (24, 1, true), (25, 1, true), (26, 1, false),
            (0, 0, false), (1, 0, false), (2, 0, false), (3, 0, false), (4, 0, false), (5, 0, false), (6, 0, false), (7, 0, false), (8, 0, false), (9, 0, false), (10, 0, false), (11, 0, false), (12, 0, false), (13, 0, false), (14, 0, false), (15, 0, false), (16, 0, false), (17, 0, false), (18, 0, false), (19, 0, false), (20, 0, false), (21, 0, false), (22, 0, false), (23, 0, false), (24, 0, false), (25, 0, false)
        ]

        let bitmap = Bitmaps.Image(cgImage: .signalDotOrgQRCode)!

        for knownQRCodePixel in knownQRCodePixels {
            let x = knownQRCodePixel.0
            let y = knownQRCodePixel.1
            let hasPixel = knownQRCodePixel.2

            XCTAssertEqual(
                bitmap.hasVisiblePixel(at: Bitmaps.Point(x: x, y: y)),
                hasPixel
            )
        }
    }

    func testSolidBluePng() {
        let bitmap = Bitmaps.Image(cgImage: .solidBluePng)!
        let bluePixel = Bitmaps.Image.Pixel(r: 58, g: 118, b: 240, a: 255)

        for x in 0..<bitmap.width {
            for y in 0..<bitmap.height {
                XCTAssertEqual(
                    bitmap.pixel(at: Bitmaps.Point(x: x, y: y)),
                    bluePixel
                )
            }
        }
    }

    func testTransparency() {
        let bitmap = Bitmaps.Image(cgImage: .topHalfSemitransparentBluePng)!

        XCTAssertEqual(
            bitmap.pixel(at: Bitmaps.Point(x: 4, y: 4)),
            Bitmaps.Image.Pixel(r: 58, g: 118, b: 240, a: 255)
        )

        XCTAssertEqual(
            bitmap.pixel(at: Bitmaps.Point(x: 4, y: 24)),
            Bitmaps.Image.Pixel(r: 29, g: 59, b: 120, a: 127)
        )
    }
}

private extension CGImage {
    static let signalDotOrgQRCode: CGImage = {
        let urlData = "https://signal.org".data(using: .utf8)

        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue("L", forKey: "inputCorrectionLevel")
        filter.setValue(urlData, forKey: "inputMessage")

        let ciImage = filter.outputImage!

        let colorParameters = [
            "inputColor0": CIColor(color: .black),
            "inputColor1": CIColor(color: .clear)
        ]

        let recoloredCIImage = ciImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        let context = CIContext(options: nil)
        return context.createCGImage(
            recoloredCIImage,
            from: ciImage.extent
        )!
    }()

    static let solidBluePng: CGImage = {
        return UIImage(
            named: "blue-rectangle",
            in: Bundle(for: BitmapsImageParsingTest.self),
            compatibleWith: nil
        )!.cgImage!
    }()

    static let topHalfSemitransparentBluePng: CGImage = {
        return UIImage(
            named: "semitransparent",
            in: Bundle(for: BitmapsImageParsingTest.self),
            compatibleWith: nil
        )!.cgImage!
    }()
}
