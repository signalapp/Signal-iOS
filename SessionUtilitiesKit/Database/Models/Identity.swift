// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import Curve25519Kit
import CryptoSwift

public struct Identity: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "identity" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case variant
        case data
    }
    
    public enum Variant: String, Codable, CaseIterable, DatabaseValueConvertible {
        case seed
        case ed25519SecretKey
        case ed25519PublicKey
        case x25519PrivateKey
        case x25519PublicKey
    }
    
    public var id: Variant { variant }
    
    let variant: Variant
    let data: Data
}

// MARK: - Convenience

extension ECKeyPair {
    func toData() -> Data {
        var targetValue: ECKeyPair = self

        return Data(bytes: &targetValue, count: MemoryLayout.size(ofValue: targetValue))
    }
}

// MARK: - GRDB Interactions

public extension Identity {
    static func generate(from seed: Data) throws -> (ed25519KeyPair: Sign.KeyPair, x25519KeyPair: ECKeyPair) {
        assert(seed.count == 16)
        let padding = Data(repeating: 0, count: 16)
        
        guard
            let ed25519KeyPair = Sodium().sign.keyPair(seed: (seed + padding).bytes),
            let x25519PublicKey = Sodium().sign.toX25519(ed25519PublicKey: ed25519KeyPair.publicKey),
            let x25519SecretKey = Sodium().sign.toX25519(ed25519SecretKey: ed25519KeyPair.secretKey)
        else {
            throw GeneralError.keyGenerationFailed
        }
        
        let x25519KeyPair = try ECKeyPair(publicKeyData: Data(x25519PublicKey), privateKeyData: Data(x25519SecretKey))
        
        return (ed25519KeyPair: ed25519KeyPair, x25519KeyPair: x25519KeyPair)
    }

    static func store(seed: Data, ed25519KeyPair: Sign.KeyPair, x25519KeyPair: ECKeyPair) {
        GRDBStorage.shared.write { db in
            try Identity(variant: .seed, data: seed).save(db)
            try Identity(variant: .ed25519SecretKey, data: Data(ed25519KeyPair.secretKey)).save(db)
            try Identity(variant: .ed25519PublicKey, data: Data(ed25519KeyPair.publicKey)).save(db)
            try Identity(variant: .x25519PrivateKey, data: x25519KeyPair.privateKey).save(db)
            try Identity(variant: .x25519PublicKey, data: x25519KeyPair.publicKey).save(db)
        }
    }
    
    static func userExists(_ db: Database? = nil) -> Bool {
        let userExists: (Database) -> Bool = { db in
            return (
                (try? Identity.fetchOne(db, id: .x25519PublicKey)) != nil &&
                (try? Identity.fetchOne(db, id: .x25519PrivateKey)) != nil
            )
        }
        
        if let db: Database = db {
            return userExists(db)
        }
        
        return GRDBStorage.shared
            .read { db -> Bool in userExists(db) }
            .defaulting(to: false)
    }
    
    static func fetchUserPublicKey(_ db: Database? = nil) -> Data? {
        if let db: Database = db {
            return try? Identity.fetchOne(db, id: .x25519PublicKey)?.data
        }
        
        return GRDBStorage.shared.read { db -> Data? in
            try Identity.fetchOne(db, id: .x25519PublicKey)?.data
        }
    }
    
    static func fetchUserPrivateKey(_ db: Database? = nil) -> Data? {
        if let db: Database = db {
            return try? Identity.fetchOne(db, id: .x25519PrivateKey)?.data
        }
        
        return GRDBStorage.shared.read { db -> Data? in
            try Identity.fetchOne(db, id: .x25519PrivateKey)?.data
        }
    }
    
    static func fetchUserKeyPair(_ db: Database? = nil) -> Box.KeyPair? {
        let fetchKeys: (Database) -> Box.KeyPair? = { db in
            guard
                let publicKey: Identity = try? Identity.fetchOne(db, id: .x25519PublicKey),
                let privateKey: Identity = try? Identity.fetchOne(db, id: .x25519PrivateKey)
            else {
                return nil
            }
            
            return Box.KeyPair(
                publicKey: publicKey.data.bytes,
                secretKey: privateKey.data.bytes
            )
        }
        
        if let db: Database = db {
            return fetchKeys(db)
        }
        
        return GRDBStorage.shared.read { db -> Box.KeyPair? in
            return fetchKeys(db)
        }
    }
    
    static func fetchUserEd25519KeyPair() -> Box.KeyPair? {
        return GRDBStorage.shared.read { db -> Box.KeyPair? in
            guard
                let publicKey: Identity = try? Identity.fetchOne(db, id: .ed25519PublicKey),
                let secretKey: Identity = try? Identity.fetchOne(db, id: .ed25519SecretKey)
            else {
                return nil
            }
            
            return Box.KeyPair(
                publicKey: publicKey.data.bytes,
                secretKey: secretKey.data.bytes
            )
        }
    }
    
    static func fetchHexEncodedSeed() -> String? {
        return GRDBStorage.shared.read { db in
            guard let value: Identity = try? Identity.fetchOne(db, id: .seed) else {
                return nil
            }
            
            return value.data.toHexString()
        }
    }
    
    static func clearAll() {
        GRDBStorage.shared.write { db in
            try Identity.deleteAll(db)
        }
    }
}

@objc(SUKIdentity)
public class objc_Identity: NSObject {
    @objc(clearAll)
    public static func objc_clearAll() {
        Identity.clearAll()
    }
}
