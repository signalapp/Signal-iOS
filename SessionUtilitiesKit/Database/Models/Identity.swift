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
        return (fetchUserKeyPair(db) != nil)
    }
    
    static func fetchUserPublicKey(_ db: Database? = nil) -> Data? {
        guard let db: Database = db else {
            return GRDBStorage.shared.read { db in fetchUserPublicKey(db) }
        }
        
        return try? Identity.fetchOne(db, id: .x25519PublicKey)?.data
    }
    
    static func fetchUserPrivateKey(_ db: Database? = nil) -> Data? {
        guard let db: Database = db else {
            return GRDBStorage.shared.read { db in fetchUserPrivateKey(db) }
        }
        
        return try? Identity.fetchOne(db, id: .x25519PrivateKey)?.data
    }
    
    static func fetchUserKeyPair(_ db: Database? = nil) -> Box.KeyPair? {
        guard let db: Database = db else {
            return GRDBStorage.shared.read { db in fetchUserKeyPair(db) }
        }
        guard
            let publicKey: Data = fetchUserPublicKey(db),
            let privateKey: Data = fetchUserPrivateKey(db)
        else { return nil }
        
        return Box.KeyPair(
            publicKey: publicKey.bytes,
            secretKey: privateKey.bytes
        )
    }
    
    static func fetchUserEd25519KeyPair() -> Box.KeyPair? {
        return GRDBStorage.shared.read { db -> Box.KeyPair? in
            guard
                let publicKey: Data = try? Identity.fetchOne(db, id: .ed25519PublicKey)?.data,
                let secretKey: Data = try? Identity.fetchOne(db, id: .ed25519SecretKey)?.data
            else { return nil }
            
            return Box.KeyPair(
                publicKey: publicKey.bytes,
                secretKey: secretKey.bytes
            )
        }
    }
    
    static func fetchHexEncodedSeed() -> String? {
        return GRDBStorage.shared.read { db in
            guard let data: Data = try? Identity.fetchOne(db, id: .seed)?.data else {
                return nil
            }
            
            return data.toHexString()
        }
    }
}
