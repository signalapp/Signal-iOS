//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class StickerPackInfoTest: XCTestCase {
    func testIsStickerPackShareUrl() throws {
        let validStrings = [
            "https://signal.art/addstickers#pack_id=abc&pack_key=def",
            "https://signal.art/addstickers",
            "https://signal.art/addstickers?ignored=true"
        ]
        for string in validStrings {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertTrue(StickerPackInfo.isStickerPackShare(url), string)
        }

        let invalidStrings = [
            // Invalid capitalization
            "HtTpS://SiGnAl.ArT/addstickers#pack_id=abc&pack_key=def",
            // Invalid protocols
            "http://signal.art/addstickers#pack_id=abc&pack_key=def",
            "signal://signal.art/addstickers#pack_id=abc&pack_key=def",
            "sgnl://signal.art/addstickers#pack_id=abc&pack_key=def",
            // Extra auth
            "https://user:pass@signal.art/addstickers#pack_id=abc&pack_key=def",
            // Invalid host
            "https://example.org/addstickers#pack_id=abc&pack_key=def",
            "https://signal.group/addstickers#pack_id=abc&pack_key=def",
            "https://signal.me/addstickers#pack_id=abc&pack_key=def",
            "https://signal.art:80/addstickers#pack_id=abc&pack_key=def",
            "https://signal.art:443/addstickers#pack_id=abc&pack_key=def",
            // Wrong path
            "https://signal.art/foo#pack_id=abc&pack_key=def"
        ]
        for string in invalidStrings {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertFalse(StickerPackInfo.isStickerPackShare(url), string)
        }
    }
}
