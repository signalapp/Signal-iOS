// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionUtilitiesKit

class SessionIdSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("a SessionId") {
            context("when initializing") {
                context("with an idString") {
                    it("succeeds when correct") {
                        let sessionId: SessionId? = SessionId(from: "05\(TestConstants.publicKey)")
                        
                        expect(sessionId?.prefix).to(equal(.standard))
                        expect(sessionId?.publicKey).to(equal(TestConstants.publicKey))
                    }
                    
                    it("fails when too short") {
                        expect(SessionId(from: "")).to(beNil())
                    }
                    
                    it("fails with an invalid prefix") {
                        expect(SessionId(from: "AB\(TestConstants.publicKey)")).to(beNil())
                    }
                }
                
                context("with a prefix and publicKey") {
                    it("converts the bytes into a hex string") {
                        let sessionId: SessionId? = SessionId(.standard, publicKey: [0, 1, 2, 3, 4, 5, 6, 7, 8])
                        
                        expect(sessionId?.prefix).to(equal(.standard))
                        expect(sessionId?.publicKey).to(equal("000102030405060708"))
                    }
                }
            }
            
            it("generates the correct hex string") {
                expect(SessionId(.unblinded, publicKey: Data(hex: TestConstants.publicKey).bytes).hexString)
                    .to(equal("0088672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                expect(SessionId(.standard, publicKey: Data(hex: TestConstants.publicKey).bytes).hexString)
                    .to(equal("0588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
                expect(SessionId(.blinded, publicKey: Data(hex: TestConstants.publicKey).bytes).hexString)
                    .to(equal("1588672ccb97f40bb57238989226cf429b575ba355443f47bc76c5ab144a96c65b"))
            }
        }
        
        describe("a SessionId Prefix") {
            context("when initializing") {
                context("with just a prefix") {
                    it("succeeds when valid") {
                        expect(SessionId.Prefix(from: "00")).to(equal(.unblinded))
                        expect(SessionId.Prefix(from: "05")).to(equal(.standard))
                        expect(SessionId.Prefix(from: "15")).to(equal(.blinded))
                    }
                    
                    it("fails when nil") {
                        expect(SessionId.Prefix(from: nil)).to(beNil())
                    }
                    
                    it("fails when invalid") {
                        expect(SessionId.Prefix(from: "AB")).to(beNil())
                    }
                }
                
                context("with a longer string") {
                    it("fails with invalid hex") {
                        expect(SessionId.Prefix(from: "Hello!!!")).to(beNil())
                    }
                    
                    it("fails with the wrong length") {
                        expect(SessionId.Prefix(from: String(TestConstants.publicKey.prefix(10)))).to(beNil())
                    }
                    
                    it("fails with an invalid prefix") {
                        expect(SessionId.Prefix(from: "AB\(TestConstants.publicKey)")).to(beNil())
                    }
                }
            }
        }
    }
}
