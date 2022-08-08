// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class NonceGeneratorSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a NonceGenerator16Byte") {
            it("has the correct number of bytes") {
                expect(OpenGroupAPI.NonceGenerator16Byte().NonceBytes).to(equal(16))
            }
        }
        
        describe("a NonceGenerator24Byte") {
            it("has the correct number of bytes") {
                expect(OpenGroupAPI.NonceGenerator24Byte().NonceBytes).to(equal(24))
            }
        }
    }
}
