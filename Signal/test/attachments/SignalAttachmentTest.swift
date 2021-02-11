//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalMessaging

class SignalAttachmentTest: SignalBaseTest {
    func testMetadataStrippingDoesNotChangeOrientation(url: URL) throws {
        let size = NSData.imageSize(forFilePath: url.path, mimeType: "image/jpeg")

        let dataSource = try DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false)
        let attachment = SignalAttachment.attachment(dataSource: dataSource,
                                                     dataUTI: kUTTypeJPEG as String,
                                                     imageQuality: .original)
        let newSize = (attachment.data as NSData).imageMetadata(withPath: nil, mimeType: "image/jpeg").pixelSize

        XCTAssertEqual(newSize, size, "image dimensions changed for \(url.lastPathComponent)")
    }

    func testMetadataStrippingDoesNotChangeOrientation() throws {
        let testBundle = Bundle(for: SignalAttachmentTest.self)
        try testMetadataStrippingDoesNotChangeOrientation(url: testBundle.url(forResource: "test-jpg",
                                                                              withExtension: "jpg")!)
        try testMetadataStrippingDoesNotChangeOrientation(url: testBundle.url(forResource: "test-jpg-rotated",
                                                                              withExtension: "jpg")!)
    }
}
