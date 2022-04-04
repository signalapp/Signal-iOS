// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Contact: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "contact" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        
        case isTrusted
        case isApproved
        case isBlocked
        case didApproveMe
        case hasBeenBlocked
    }

    /// The id for the contact (Note: This could be a sessionId, a blindedId or some future variant)
    public let id: String
    
    /// This flag is used to determine whether we should auto-download files sent by this contact.
    public var isTrusted = false
    
    /// This flag is used to determine whether message requests from this contact are approved
    public var isApproved = false
    
    /// This flag is used to determine whether message requests from this contact are blocked
    public var isBlocked = false {
        didSet {
            if isBlocked {
                hasBeenBlocked = true
            }
        }
    }
    
    /// This flag is used to determine whether this contact has approved the current users message request
    public var didApproveMe = false
    
    /// This flag is used to determine whether this contact has ever been blocked (will be included in the config message if so)
    public var hasBeenBlocked = false
}
