// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class BlindedIdLookupSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a BlindedIdLookup") {
            context("when initializing") {
                it("sets the values correctly") {
                    let lookup: BlindedIdLookup = BlindedIdLookup(
                        blindedId: "testBlindedId",
                        sessionId: "testSessionId",
                        openGroupServer: "testServer",
                        openGroupPublicKey: "testPublicKey"
                    )
                    
                    expect(lookup.blindedId).to(equal("testBlindedId"))
                    expect(lookup.sessionId).to(equal("testSessionId"))
                    expect(lookup.openGroupServer).to(equal("testServer"))
                    expect(lookup.openGroupPublicKey).to(equal("testPublicKey"))
                }
            }
        }
    }
}
