// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Contact: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "contact" }
    internal static let threadForeignKey = ForeignKey([Columns.id], to: [SessionThread.Columns.id])
    public static let profile = hasOne(Profile.self, using: Profile.contactForeignKey)
    
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
    public let isTrusted: Bool
    
    /// This flag is used to determine whether message requests from this contact are approved
    public let isApproved: Bool
    
    /// This flag is used to determine whether message requests from this contact are blocked
    public let isBlocked: Bool
    
    /// This flag is used to determine whether this contact has approved the current users message request
    public let didApproveMe: Bool
    
    /// This flag is used to determine whether this contact has ever been blocked (will be included in the config message if so)
    public let hasBeenBlocked: Bool
    
    // MARK: - Relationships
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Contact.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        id: String,
        isTrusted: Bool = false,
        isApproved: Bool = false,
        isBlocked: Bool = false,
        didApproveMe: Bool = false,
        hasBeenBlocked: Bool = false
    ) {
        self.id = id
        self.isTrusted = (
            isTrusted ||
            id == getUserHexEncodedPublicKey()  // Always trust ourselves
        )
        self.isApproved = isApproved
        self.isBlocked = isBlocked
        self.didApproveMe = didApproveMe
        self.hasBeenBlocked = (isBlocked || hasBeenBlocked)
    }
}

// MARK: - Convenience

public extension Contact {
    func with(
        isTrusted: Updatable<Bool> = .existing,
        isApproved: Updatable<Bool> = .existing,
        isBlocked: Updatable<Bool> = .existing,
        didApproveMe: Updatable<Bool> = .existing
    ) -> Contact {
        return Contact(
            id: id,
            isTrusted: (
                (isTrusted ?? self.isTrusted) ||
                self.id == getUserHexEncodedPublicKey() // Always trust ourselves
            ),
            isApproved: (isApproved ?? self.isApproved),
            isBlocked: (isBlocked ?? self.isBlocked),
            didApproveMe: (didApproveMe ?? self.didApproveMe),
            hasBeenBlocked: ((isBlocked ?? self.isBlocked) || self.hasBeenBlocked)
        )
    }
}

// MARK: - GRDB Interactions

public extension Contact {
    /// Fetches or creates a Contact for the specified user
    ///
    /// **Note:** This method intentionally does **not** save the newly created Contact,
    /// it will need to be explicitly saved after calling
    static func fetchOrCreate(_ db: Database, id: ID) -> Contact {
        return ((try? fetchOne(db, id: id)) ?? Contact(id: id))
    }
}

// MARK: - Objective-C Support

// TODO: Remove this when possible
@objc(SMKContact)
public class SMKContact: NSObject {
    @objc(isBlockedFor:)
    public static func isBlocked(id: String) -> Bool {
        return Storage.shared
            .read { db in
                try Contact
                    .filter(id: id)
                    .select(.isBlocked)
                    .asRequest(of: Bool.self)
                    .fetchOne(db)
            }
            .defaulting(to: false)
    }
}
