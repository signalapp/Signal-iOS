//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import GRDB
import LibSignalClient
public import SignalRingRTC

/// Responsible for the colors used for default "initials over colored
/// background" avatars.
///
/// For new chats, these are locally derived based on some information about the
/// chat. However, clients historically performed that derivation using
/// different algorithms. We want to display consistent colors for chats using
/// the default avatar, so these are synced across clients and stored.
public struct AvatarDefaultColorManager {
    public enum UseCase {
        case contact(recipient: SignalRecipient)
        case contactWithoutRecipient(address: SignalServiceAddress)
        case group(groupId: Data)
        case callLink(rootKey: CallLinkRootKey)
    }

    init() {}

    /// Derive the default color for the given use case. Callers should prefer
    /// `defaultColor(useCase:tx:)` unless they know a color is never persisted
    /// for the given use case.
    public static func deriveDefaultColor(useCase: UseCase) -> AvatarTheme {
        guard let index = deriveIndex(useCase: useCase) else {
            return .default
        }
        return .forIndex(index)
    }

    public static func deriveGradient(useCase: UseCase) -> AvatarGradient {
        guard let index = deriveIndex(useCase: useCase) else {
            return AvatarGradient.gradients[0]
        }
        return AvatarGradient.gradients[index % AvatarGradient.gradients.count]
    }

    private static func deriveIndex(useCase: UseCase) -> Int? {
        let seedData: Data
        switch useCase {
        case .contact(let recipient):
            if let aci = recipient.aci {
                seedData = aci.serviceIdBinary
            } else if let phoneNumber = recipient.phoneNumber {
                seedData = Data(phoneNumber.stringValue.utf8)
            } else if let pni = recipient.pni {
                seedData = pni.serviceIdBinary
            } else {
                return nil
            }
        case .contactWithoutRecipient(let address):
            if let aci = address.serviceId as? Aci {
                seedData = aci.serviceIdBinary
            } else if let phoneNumber = address.phoneNumber {
                seedData = Data(phoneNumber.utf8)
            } else if let pni = address.serviceId as? Pni {
                seedData = pni.serviceIdBinary
            } else {
                return nil
            }
        case .group(let groupId):
            seedData = groupId
        case .callLink(let rootKey):
            // Per spec, these don't go through SHA256 to determine the color.
            return Int(rootKey.bytes.first!)
        }

        // We'll take a SHA256 hash of the seed, and then use the first byte of
        // the hash as the index of the color to use.
        var sha256 = SHA256()
        sha256.update(data: seedData)
        guard let firstSHA256Byte = Data(sha256.finalize()).first else {
            owsFailDebug("Unexpectedly empty SHA256!")
            return nil
        }

        // The indexing uses modulo internally, so we can pass an arbitrarily
        // large index.
        return Int(firstSHA256Byte)
    }

    // MARK: -

    /// Returns the default avatar color for the given use case. Returns a
    /// persisted color if one exists, or one derived for the use case if not.
    public func defaultColor(
        useCase: UseCase,
        tx: DBReadTransaction,
    ) -> AvatarTheme {
        let persistedColorRecord: AvatarDefaultColorRecord?
        switch useCase {
        case .callLink:
            // At the time of writing we don't persist these.
            persistedColorRecord = nil
        case .contactWithoutRecipient:
            // We only persist for contacts with recipients, which will cover
            // anyone we've messaged with directly.
            persistedColorRecord = nil
        case .contact(let recipient):
            do {
                persistedColorRecord = try AvatarDefaultColorRecord
                    .filter(Column(AvatarDefaultColorRecord.CodingKeys.recipientRowId) == recipient.id)
                    .fetchOne(tx.database)
            } catch let error {
                owsFailDebug("Failed to fetch default color record for recipient: \(error.grdbErrorForLogging)")
                persistedColorRecord = nil
            }
        case .group(let groupId):
            do {
                persistedColorRecord = try AvatarDefaultColorRecord
                    .filter(Column(AvatarDefaultColorRecord.CodingKeys.groupId) == groupId)
                    .fetchOne(tx.database)
            } catch let error {
                owsFailDebug("Failed to fetch default color record for group: \(error.grdbErrorForLogging)")
                persistedColorRecord = nil
            }
        }

        if let persistedColorRecord {
            return persistedColorRecord.defaultColor
        } else {
            // If we haven't persisted something to use instead, we can derive a
            // value!
            return Self.deriveDefaultColor(useCase: useCase)
        }
    }

    // MARK: -

    func persistDefaultColor(
        _ defaultColor: AvatarTheme,
        recipientRowId: SignalRecipient.RowId,
        tx: DBWriteTransaction,
    ) throws {
        try persistDefaultColor(
            record: AvatarDefaultColorRecord(
                recipientRowId: recipientRowId,
                defaultColor: defaultColor,
            ),
            tx: tx,
        )
    }

    func persistDefaultColor(
        _ defaultColor: AvatarTheme,
        groupId: Data,
        tx: DBWriteTransaction,
    ) throws {
        try persistDefaultColor(
            record: AvatarDefaultColorRecord(
                groupId: groupId,
                defaultColor: defaultColor,
            ),
            tx: tx,
        )
    }

    private func persistDefaultColor(
        record: AvatarDefaultColorRecord,
        tx: DBWriteTransaction,
    ) throws {
        // These records treat conflict-on-insert as an update, so this is
        // really an upsert.
        try record.insert(tx.database)
    }
}

// MARK: -

private struct AvatarDefaultColorRecord: Codable, PersistableRecord, FetchableRecord {
    static let databaseTableName: String = "AvatarDefaultColor"

    /// Part of ``GRDB.MutablePersistableRecord``. If we get a conflict while
    /// inserting (or updating, although I'm not sure how that can conflict),
    /// update instead. (In effect, treat `insert` as `upsert`.)
    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace,
    )

    enum CodingKeys: String, CodingKey {
        case recipientRowId
        case groupId
        case defaultColorIndex
    }

    /// A ``SignalRecipient/id``, whose contact's default avatar color this
    /// record describes.
    let recipientRowId: Int64?
    /// A group ID, whose group's default avatar color this record describes.
    let groupId: Data?
    /// An index into the list of default avatar colors.
    private let defaultColorIndex: Int

    var defaultColor: AvatarTheme { .forIndex(defaultColorIndex) }

    init(recipientRowId: Int64, defaultColor: AvatarTheme) {
        self.init(
            recipientRowId: recipientRowId,
            groupId: nil,
            defaultColor: defaultColor,
        )
    }

    init(groupId: Data, defaultColor: AvatarTheme) {
        self.init(
            recipientRowId: nil,
            groupId: groupId,
            defaultColor: defaultColor,
        )
    }

    private init(
        recipientRowId: Int64?,
        groupId: Data?,
        defaultColor: AvatarTheme,
    ) {
        self.recipientRowId = recipientRowId
        self.groupId = groupId
        self.defaultColorIndex = AvatarTheme.index(of: defaultColor)
    }
}

// MARK: -

private extension AvatarTheme {
    static func forIndex(_ index: Int) -> AvatarTheme {
        AvatarTheme.allCases[index % AvatarTheme.allCases.count]
    }

    static func index(of theme: AvatarTheme) -> Int {
        AvatarTheme.allCases.firstIndex(of: theme)!
    }
}
