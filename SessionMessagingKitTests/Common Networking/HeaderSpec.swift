// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class HeaderSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a Dictionary of Header to String values") {
            it("can be converted into a dictionary of String to String values") {
                expect([Header.authorization: "test"].toHTTPHeaders()).to(equal(["Authorization": "test"]))
            }
        }
    }
}
