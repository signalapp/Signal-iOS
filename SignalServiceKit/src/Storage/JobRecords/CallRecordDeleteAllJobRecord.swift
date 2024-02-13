//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class CallRecordDeleteAllJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecord.JobRecordType { .callRecordDeleteAll }

    let sendDeleteAllSyncMessage: Bool
    let deleteAllBeforeTimestamp: UInt64

    init(
        sendDeleteAllSyncMessage: Bool,
        deleteAllBeforeTimestamp: UInt64,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.sendDeleteAllSyncMessage = sendDeleteAllSyncMessage
        self.deleteAllBeforeTimestamp = deleteAllBeforeTimestamp

        super.init(
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sendDeleteAllSyncMessage = try container.decode(Bool.self, forKey: .sendDeleteAllSyncMessage)
        deleteAllBeforeTimestamp = try container.decode(UInt64.self, forKey: .deleteAllBeforeTimestamp)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(sendDeleteAllSyncMessage, forKey: .sendDeleteAllSyncMessage)
        try container.encode(deleteAllBeforeTimestamp, forKey: .deleteAllBeforeTimestamp)
    }
}
