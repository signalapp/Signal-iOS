// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class SodiumProtocolsSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("an AeadXChaCha20Poly1305IetfType") {
            let testValue: [UInt8] = [1, 2, 3]
            
            it("provides the default values in it's extensions") {
                let testAead: TestAeadXChaCha20Poly1305Ietf = TestAeadXChaCha20Poly1305Ietf()
                testAead.mockData[.encrypt] = testValue
                testAead.mockData[.decrypt] = testValue
                
                expect(testAead.encrypt(message: [], secretKey: [], nonce: [])).to(equal(testValue))
                expect(testAead.encrypt(message: [], secretKey: [], nonce: [], additionalData: nil)).to(equal(testValue))
                expect(testAead.decrypt(authenticatedCipherText: [], secretKey: [], nonce: [])).to(equal(testValue))
                expect(testAead.decrypt(authenticatedCipherText: [], secretKey: [], nonce: [], additionalData: nil))
                    .to(equal(testValue))
            }
        }
        
        describe("a GenericHashType") {
            let testValue: [UInt8] = [1, 2, 3]
            
            it("provides the default values in it's extensions") {
                let testGenericHash: TestGenericHash = TestGenericHash()
                testGenericHash.mockData[.hash] = testValue
                testGenericHash.mockData[.hashSaltPersonal] = testValue
                
                expect(testGenericHash.hash(message: [])).to(equal(testValue))
                expect(testGenericHash.hash(message: [], key: nil)).to(equal(testValue))
                expect(testGenericHash.hashSaltPersonal(message: [], outputLength: 0, salt: [], personal: []))
                    .to(equal(testValue))
                expect(testGenericHash.hashSaltPersonal(message: [], outputLength: 0, key: nil, salt: [], personal: []))
                    .to(equal(testValue))
            }
        }
    }
}
