//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalUI

class StorySharingTests: XCTestCase {
    func testUrlStripping() {
        let inputOutput = [
            "https://signal.org test": "test",
            "https://signal.orgtest test https://signal.org": "https://signal.orgtest test",
            "testhttps://signal.org": "testhttps://signal.org",
            "test\nhttps://signal.org": "test",
            "https://signal.org\ntest": "test",
            "https://signal.org\ntest\nhttps://signal.org": "test\nhttps://signal.org",
            "some https://signal.org test": "some https://signal.org test",
            "https://signal.org": nil,
            "something else": "something else"
        ]

        for (input, expectedOutput) in inputOutput {
            let output = StorySharing.text(
                for: .init(
                    text: input,
                    ranges: .empty
                ),
                with: OWSLinkPreview(
                    urlString: "https://signal.org",
                    title: nil,
                    imageAttachmentId: nil
                )
            )
            XCTAssertEqual(output, expectedOutput)
        }
    }
}
