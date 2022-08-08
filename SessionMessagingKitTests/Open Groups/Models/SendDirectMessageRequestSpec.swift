// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class SendDirectMessageRequestSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a SendDirectMessageRequest") {
            context("when encoding") {
                it("encodes the data as a base64 string") {
                    let request: OpenGroupAPI.SendDirectMessageRequest = OpenGroupAPI.SendDirectMessageRequest(
                        message: "TestData".data(using: .utf8)!
                    )
                    let requestData: Data = try! JSONEncoder().encode(request)
                    let requestDataString: String = String(data: requestData, encoding: .utf8)!
                    
                    expect(requestDataString).toNot(contain("TestData"))
                    expect(requestDataString).to(contain("VGVzdERhdGE="))
                }
            }
        }
    }
}
