// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class ServerSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("an Open Group Server") {
            context("when initializing") {
                it("converts the server name to lowercase") {
                    let server: OpenGroupAPI.Server = OpenGroupAPI.Server(
                        name: "TeSt",
                        capabilities: OpenGroupAPI.Capabilities(capabilities: [], missing: nil)
                    )
                    
                    expect(server.name).to(equal("test"))
                }
            }
            
            context("when NSCoding") {
                // Note: Unit testing NSCoder is horrible so we won't do it properly - wait until we refactor it to Codable
                it("successfully encodes and decodes") {
                    let serverToEncode: OpenGroupAPI.Server = OpenGroupAPI.Server(
                        name: "test",
                        capabilities: OpenGroupAPI.Capabilities(
                            capabilities: [.sogs, .unsupported("other")],
                            missing: [.blind, .unsupported("other2")])
                    )
                    let encodedData: Data = try! NSKeyedArchiver.archivedData(withRootObject: serverToEncode, requiringSecureCoding: false)
                    let server: OpenGroupAPI.Server? = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as? OpenGroupAPI.Server
                    
                    expect(server).toNot(beNil())
                    expect(server?.name).to(equal("test"))
                    expect(server?.capabilities.capabilities).to(equal([.sogs, .unsupported("other")]))
                    expect(server?.capabilities.missing).to(equal([.blind, .unsupported("other2")]))
                }
            }
            
            context("when describing") {
                it("includes relevant information") {
                    let server: OpenGroupAPI.Server = OpenGroupAPI.Server(
                        name: "TeSt",
                        capabilities: OpenGroupAPI.Capabilities(
                            capabilities: [.sogs, .unsupported("other")],
                            missing: [.blind, .unsupported("other2")]
                        )
                    )
                    
                    expect(server.description)
                        .to(equal("test (Capabilities: [sogs, other], Missing: [blind, other2])"))
                }
                
                it("handles nil missing capabilities") {
                    let server: OpenGroupAPI.Server = OpenGroupAPI.Server(
                        name: "TeSt",
                        capabilities: OpenGroupAPI.Capabilities(
                            capabilities: [.sogs, .unsupported("other")],
                            missing: nil
                        )
                    )
                    
                    expect(server.description)
                        .to(equal("test (Capabilities: [sogs, other], Missing: [])"))
                }
            }
        }
    }
}
