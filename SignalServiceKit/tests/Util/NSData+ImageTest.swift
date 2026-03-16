//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

class NSDataImageTests {
    @Test
    func testIsNotAnimatedPng() {
        let image = UIImage.image(color: .red, size: CGSize(width: 1, height: 1))
        let data = image.pngData()!
        let isApng = DataImageSource(data).imageMetadata()?.isAnimated
        #expect(isApng == false)
    }

    @Test
    func testIsAnimatedPng() {
        let data: Data = {
            let testBundle = Bundle(for: Self.self)
            let url = testBundle.url(forResource: "test-apng", withExtension: "png")!
            return try! Data(contentsOf: url)
        }()
        let isApng = DataImageSource(data).imageMetadata()?.isAnimated
        #expect(isApng == true)
    }
}
