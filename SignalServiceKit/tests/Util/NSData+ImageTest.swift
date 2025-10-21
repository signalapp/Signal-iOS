//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class NSDataImageTests: XCTestCase {

    func testIsAnimatedPngData_png() {
        let image = UIImage.image(color: .red, size: CGSize(width: 1, height: 1))
        let data = image.pngData()!
        let isApng = DataImageSource(data).isAnimatedPng()
        XCTAssertEqual(isApng, false)
    }

    func testIsAnimatedPngData_apng() {
        let data: Data = {
            let testBundle = Bundle(for: Self.self)
            let url = testBundle.url(forResource: "test-apng", withExtension: "png")!
            return try! Data(contentsOf: url)
        }()
        let isApng = DataImageSource(data).isAnimatedPng()
        XCTAssertEqual(isApng, true)
    }

    func testIsAnimatedPngData_invalid() {
        do {
            let data = Randomness.generateRandomBytes(0)
            let isApng = DataImageSource(data).isAnimatedPng()
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(1)
            let isApng = DataImageSource(data).isAnimatedPng()
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(64)
            let isApng = DataImageSource(data).isAnimatedPng()
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(1024)
            let isApng = DataImageSource(data).isAnimatedPng()
            XCTAssertNil(isApng)
        }
    }
}
