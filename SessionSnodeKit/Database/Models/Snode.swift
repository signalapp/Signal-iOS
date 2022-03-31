// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Snode: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible, Hashable {
    public static var databaseTableName: String { "snode" }
    
    public enum Columns: String, CodingKey, ColumnExpression {
        case address
        case port
        case ed25519PublicKey
        case x25519PublicKey
    }
    
    let address: String
    let port: UInt16
    let ed25519PublicKey: String
    let x25519PublicKey: String
}
