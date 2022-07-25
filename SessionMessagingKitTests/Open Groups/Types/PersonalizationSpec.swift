// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class PersonalizationSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a Personalization") {
            it("generates bytes correctly") {
                expect(OpenGroupAPI.Personalization.sharedKeys.bytes)
                    .to(equal([115, 111, 103, 115, 46, 115, 104, 97, 114, 101, 100, 95, 107, 101, 121, 115]))
                expect(OpenGroupAPI.Personalization.authHeader.bytes)
                    .to(equal([115, 111, 103, 115, 46, 97, 117, 116, 104, 95, 104, 101, 97, 100, 101, 114]))
            }
        }
    }
}
