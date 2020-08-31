//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class NSDataImageTests: SSKBaseTestSwift {

    func testIsAnimatedPngData_apng1() {
        let filePath = "/Users/matthew/Downloads/sample-apng-1.png"
        let fileUrl = URL(fileURLWithPath: filePath)
        let data = try! Data(contentsOf: fileUrl)
        let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
        XCTAssertNotNil(isApng)
        XCTAssertTrue(isApng!.boolValue)
    }

    func testIsAnimatedPngData_apng2() {
        let filePath = "/Users/matthew/Downloads/sample-apng-2.png"
        let fileUrl = URL(fileURLWithPath: filePath)
        let data = try! Data(contentsOf: fileUrl)
        let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
        XCTAssertNotNil(isApng)
        XCTAssertTrue(isApng!.boolValue)
    }

    func testIsAnimatedPngData_png() {
        let image = UIImage(color: .red, size: CGSize(width: 1, height: 1))
        let data = image.pngData()!
        let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
        XCTAssertNotNil(isApng)
        XCTAssertFalse(isApng!.boolValue)
    }

    func testIsAnimatedPngData_invalid() {
        do {
            let data = Randomness.generateRandomBytes(0)
            let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(1)
            let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(64)
            let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
            Logger.verbose("isApng: \(isApng)")
            XCTAssertNil(isApng)
        }
        do {
            let data = Randomness.generateRandomBytes(1024)
            let isApng: NSNumber? = (data as NSData).isAnimatedPngData()
            Logger.verbose("isApng: \(isApng)")
            XCTAssertNil(isApng)
        }
    }
}
