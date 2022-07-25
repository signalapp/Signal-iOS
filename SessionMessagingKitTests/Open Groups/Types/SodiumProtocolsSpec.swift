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
                let mockAead: MockAeadXChaCha20Poly1305Ietf = MockAeadXChaCha20Poly1305Ietf()
                mockAead
                    .when {
                        $0.encrypt(
                            message: anyArray(),
                            secretKey: anyArray(),
                            nonce: anyArray(),
                            additionalData: anyArray()
                        )
                    }
                    .thenReturn(testValue)
                mockAead
                    .when {
                        $0.decrypt(
                            authenticatedCipherText: anyArray(),
                            secretKey: anyArray(),
                            nonce: anyArray(),
                            additionalData: anyArray()
                        )
                    }
                    .thenReturn(testValue)
                
                _ = mockAead.encrypt(message: [], secretKey: [], nonce: [])
                _ = mockAead.decrypt(authenticatedCipherText: [], secretKey: [], nonce: [])
                
                expect(mockAead)
                    .to(call {
                        $0.encrypt(message: anyArray(), secretKey: anyArray(), nonce: anyArray(), additionalData: anyArray())
                    })
                
                expect(mockAead)
                    .to(call {
                        $0.decrypt(
                            authenticatedCipherText: anyArray(),
                            secretKey: anyArray(),
                            nonce: anyArray(),
                            additionalData: anyArray()
                        )
                    })
            }
        }
        
        describe("a GenericHashType") {
            let testValue: [UInt8] = [1, 2, 3]
            
            it("provides the default values in it's extensions") {
                let mockGenericHash: MockGenericHash = MockGenericHash()
                mockGenericHash
                    .when { $0.hash(message: anyArray(), key: anyArray()) }
                    .thenReturn(testValue)
                mockGenericHash
                    .when {
                        $0.hashSaltPersonal(
                            message: anyArray(),
                            outputLength: any(),
                            key: anyArray(),
                            salt: anyArray(),
                            personal: anyArray()
                        )
                    }
                    .thenReturn(testValue)
                
                _ = mockGenericHash.hash(message: [])
                _ = mockGenericHash.hashSaltPersonal(message: [], outputLength: 0, salt: [], personal: [])
                
                expect(mockGenericHash)
                    .to(call { $0.hash(message: anyArray(), key: anyArray()) })
                expect(mockGenericHash)
                    .to(call {
                        $0.hashSaltPersonal(
                            message: anyArray(),
                            outputLength: any(),
                            key: anyArray(),
                            salt: anyArray(),
                            personal: anyArray()
                        )
                    })
            }
        }
    }
}
