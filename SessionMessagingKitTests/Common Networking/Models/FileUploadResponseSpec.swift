// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class FileUploadResponseSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a FileUploadResponse") {
            context("when decoding") {
                it("handles a string id value") {
                    let jsonData: Data = "{\"id\":\"123\"}".data(using: .utf8)!
                    let response: FileUploadResponse? = try? JSONDecoder().decode(FileUploadResponse.self, from: jsonData)
                    
                    expect(response?.id).to(equal("123"))
                }
                
                it("handles an int id value") {
                    let jsonData: Data = "{\"id\":124}".data(using: .utf8)!
                    let response: FileUploadResponse? = try? JSONDecoder().decode(FileUploadResponse.self, from: jsonData)
                    
                    expect(response?.id).to(equal("124"))
                }
            }
        }
    }
}
