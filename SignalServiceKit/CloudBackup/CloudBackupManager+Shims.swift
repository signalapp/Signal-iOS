//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum CloudBackup {}

extension CloudBackup {
    public enum Shims {
        public typealias SignalRecipientFetcher = _CloudBackup_SignalRecipientShim
        public typealias TSInteractionFetcher = _CloudBackup_TSInteractionShim
        public typealias TSThreadFetcher = _CloudBackup_TSThreadShim
    }

    public enum Wrappers {
        public typealias SignalRecipientFetcher = _CloudBackup_SignalRecipientWrapper
        public typealias TSInteractionFetcher = _CloudBackup_TSInteractionWrapper
        public typealias TSThreadFetcher = _CloudBackup_TSThreadWrapper
    }
}

// MARK: - SignalRecipient

public protocol _CloudBackup_SignalRecipientShim {

    func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void)
}

public class _CloudBackup_SignalRecipientWrapper: _CloudBackup_SignalRecipientShim {

    public init() {}

    public func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void) {
        SignalRecipient.anyEnumerate(
            transaction: SDSDB.shimOnlyBridge(tx),
            block: { recipient, _ in
                block(recipient)
            }
        )
    }
}

// MARK: - TSInteraction

public protocol _CloudBackup_TSInteractionShim {

    func enumerateAllTextOnlyMessages(tx: DBReadTransaction, block: @escaping (TSMessage) -> Void)
}

public class _CloudBackup_TSInteractionWrapper: _CloudBackup_TSInteractionShim {

    public init() {}

    public func enumerateAllTextOnlyMessages(tx: DBReadTransaction, block: @escaping (TSMessage) -> Void) {
        let emptyArraySerializedData = try! NSKeyedArchiver.archivedData(withRootObject: [String](), requiringSecureCoding: true)

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE (
                interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.outgoingMessage.rawValue)
                OR interaction.\(interactionColumn: .recordType) IS \(SDSRecordType.incomingMessage.rawValue)
            )
            AND (
                \(interactionColumn: .attachmentIds) IS NULL
                OR \(interactionColumn: .attachmentIds) == ?
            )
        """
        let arguments: StatementArguments = [emptyArraySerializedData]
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: arguments,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        do {
            while let interaction = try cursor.next() {
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                    continue
                }

                block(message)
            }
        } catch {
            owsFailDebug("Failed to enumerate messages!")
        }
    }
}

// MARK: - TSThread

public protocol _CloudBackup_TSThreadShim {

    func enumerateAll(tx: DBReadTransaction, block: @escaping (TSThread) -> Void)
}

public class _CloudBackup_TSThreadWrapper: _CloudBackup_TSThreadShim {

    public init() {}

    public func enumerateAll(tx: DBReadTransaction, block: @escaping (TSThread) -> Void) {
        TSThread.anyEnumerate(
            transaction: SDSDB.shimOnlyBridge(tx),
            block: { thread, _ in
                block(thread)
            }
        )
    }
}
