//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit
@testable import SignalUI

class StorySharingTests: SignalBaseTest {
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
                with: OWSLinkPreviewDraft(
                    url: URL(string: "https://signal.org")!,
                    title: nil
                )
            )?.text
            XCTAssertEqual(output, expectedOutput)
        }
    }

    func testMentionFlattening() {
        let mentionAci = Aci.randomForTesting()
        let range = NSRange(location: 0, length: MessageBody.mentionPlaceholder.utf16.count)
        let output = StorySharing.text(
            for: .init(
                text: "\(MessageBody.mentionPlaceholder) Some text",
                ranges: .init(mentions: [range: mentionAci], styles: [])
            ),
            with: nil
        )?.text

        XCTAssertEqual(output, "@Fake name Some text")
    }
}
