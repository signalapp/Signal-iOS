//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

final class LegacyMessageDecryptJobRecord: JobRecord, FactoryInitializableFromRecordType {
    static let defaultLabel: String = "SSKMessageDecrypt"

    override class var jobRecordType: JobRecordType { .legacyMessageDecrypt }

    public let envelopeData: Data?
    public let serverDeliveryTimestamp: UInt64

    public init(
        envelopeData: Data?,
        serverDeliveryTimestamp: UInt64,
        label: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.envelopeData = envelopeData
        self.serverDeliveryTimestamp = serverDeliveryTimestamp

        super.init(
            label: label,
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        envelopeData = try container.decodeIfPresent(Data.self, forKey: .envelopeData)
        serverDeliveryTimestamp = try container.decode(UInt64.self, forKey: .serverDeliveryTimestamp)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encodeIfPresent(envelopeData, forKey: .envelopeData)
        try container.encode(serverDeliveryTimestamp, forKey: .serverDeliveryTimestamp)
    }
}
