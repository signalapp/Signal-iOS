// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class BlindedIdMappingSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a BlindedIdMapping") {
            context("when initializing") {
                it("sets the values correctly") {
                    let mapping: BlindedIdMapping = BlindedIdMapping(
                        blindedId: "testBlindedId",
                        sessionId: "testSessionId",
                        serverPublicKey: "testPublicKey"
                    )
                    
                    expect(mapping.blindedId).to(equal("testBlindedId"))
                    expect(mapping.sessionId).to(equal("testSessionId"))
                    expect(mapping.serverPublicKey).to(equal("testPublicKey"))
                }
            }
            
            context("when NSCoding") {
                // Note: Unit testing NSCoder is horrible so we won't do it properly - wait until we refactor it to Codable
                it("successfully encodes and decodes") {
                    let mappingToEncode: BlindedIdMapping = BlindedIdMapping(
                        blindedId: "testBlindedId",
                        sessionId: "testSessionId",
                        serverPublicKey: "testPublicKey"
                    )
                    let encodedData: Data = try! NSKeyedArchiver.archivedData(withRootObject: mappingToEncode, requiringSecureCoding: false)
                    let mapping: BlindedIdMapping? = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as? BlindedIdMapping
                    
                    expect(mapping).toNot(beNil())
                    expect(mapping?.blindedId).to(equal("testBlindedId"))
                    expect(mapping?.sessionId).to(equal("testSessionId"))
                    expect(mapping?.serverPublicKey).to(equal("testPublicKey"))
                }
            }
        }
    }
}
