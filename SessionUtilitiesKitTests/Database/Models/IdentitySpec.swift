// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

import Quick
import Nimble

@testable import SessionUtilitiesKit

class IdentitySpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        
        describe("an Identity") {
            beforeEach {
                mockStorage = Storage(
                    customWriter: try! DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations()
                    ]
                )
            }
            
            it("correctly retrieves the user user public key") {
                mockStorage.write { db in
                    try Identity(variant: .x25519PublicKey, data: "Test1".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    expect(Identity.fetchUserPublicKey(db))
                        .to(equal("Test1".data(using: .utf8)))
                }
            }
            
            it("correctly retrieves the user private key") {
                mockStorage.write { db in
                    try Identity(variant: .x25519PrivateKey, data: "Test2".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    expect(Identity.fetchUserPrivateKey(db))
                        .to(equal("Test2".data(using: .utf8)))
                }
            }
            
            it("correctly retrieves the user key pair") {
                mockStorage.write { db in
                    try Identity(variant: .x25519PublicKey, data: "Test3".data(using: .utf8)!).insert(db)
                    try Identity(variant: .x25519PrivateKey, data: "Test4".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    let keyPair = Identity.fetchUserKeyPair(db)
                    
                    expect(keyPair?.publicKey)
                        .to(equal("Test3".data(using: .utf8)?.bytes))
                    expect(keyPair?.secretKey)
                        .to(equal("Test4".data(using: .utf8)?.bytes))
                }
            }
            
            it("correctly determines if the user exists") {
                mockStorage.write { db in
                    try Identity(variant: .x25519PublicKey, data: "Test3".data(using: .utf8)!).insert(db)
                    try Identity(variant: .x25519PrivateKey, data: "Test4".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    expect(Identity.userExists(db))
                        .to(equal(true))
                }
            }
            
            it("correctly retrieves the user ED25519 key pair") {
                mockStorage.write { db in
                    try Identity(variant: .ed25519PublicKey, data: "Test5".data(using: .utf8)!).insert(db)
                    try Identity(variant: .ed25519SecretKey, data: "Test6".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    let keyPair = Identity.fetchUserEd25519KeyPair(db)
                    
                    expect(keyPair?.publicKey)
                        .to(equal("Test5".data(using: .utf8)?.bytes))
                    expect(keyPair?.secretKey)
                        .to(equal("Test6".data(using: .utf8)?.bytes))
                }
            }
            
            it("correctly retrieves the hex encoded seed") {
                mockStorage.write { db in
                    try Identity(variant: .seed, data: "Test7".data(using: .utf8)!).insert(db)
                }
                
                mockStorage.read { db in
                    expect(Identity.fetchHexEncodedSeed(db))
                        .to(equal("5465737437"))
                }
            }
        }
    }
}
