// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class CapabilitiesSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("Capabilities") {
            context("when initializing") {
                it("assigns values correctly") {
                    let capabilities: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(
                        capabilities: [.sogs],
                        missing: [.sogs]
                    )
                    
                    expect(capabilities.capabilities).to(equal([.sogs]))
                    expect(capabilities.missing).to(equal([.sogs]))
                }
                
                it("defaults missing to nil") {
                    let capabilities: OpenGroupAPI.Capabilities = OpenGroupAPI.Capabilities(
                        capabilities: [.sogs]
                    )
                    
                    expect(capabilities.capabilities).to(equal([.sogs]))
                    expect(capabilities.missing).to(beNil())
                }
            }
        }
        
        describe("a Capability") {
            context("when initializing") {
                it("succeeeds with a valid case") {
                    let capability: Capability.Variant = Capability.Variant(
                        from: "sogs"
                    )
                    
                    expect(capability).to(equal(.sogs))
                }
                
                it("wraps an unknown value in the unsupported case") {
                    let capability: Capability.Variant = Capability.Variant(
                        from: "test"
                    )
                    
                    expect(capability).to(equal(.unsupported("test")))
                }
            }
            
            context("when accessing the rawValue") {
                it("provides known cases exactly") {
                    expect(Capability.Variant.sogs.rawValue).to(equal("sogs"))
                    expect(Capability.Variant.blind.rawValue).to(equal("blind"))
                }
                
                it("provides the wrapped value for unsupported cases") {
                    expect(Capability.Variant.unsupported("test").rawValue).to(equal("test"))
                }
            }
            
            context("when Decoding") {
                it("decodes known cases exactly") {
                    expect(
                        try? JSONDecoder().decode(
                            Capability.Variant.self,
                            from: "\"sogs\"".data(using: .utf8)!
                        )
                    )
                    .to(equal(.sogs))
                    expect(
                        try? JSONDecoder().decode(
                            Capability.Variant.self,
                            from: "\"blind\"".data(using: .utf8)!
                        )
                    )
                    .to(equal(.blind))
                }
                
                it("decodes unknown cases into the unsupported case") {
                    expect(
                        try? JSONDecoder().decode(
                            Capability.Variant.self,
                            from: "\"test\"".data(using: .utf8)!
                        )
                    )
                    .to(equal(.unsupported("test")))
                }
            }
        }
    }
}
