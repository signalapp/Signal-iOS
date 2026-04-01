//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - AttachmentBackfillRequestSyncMessage

@objc(AttachmentBackfillRequestSyncMessage)
final class AttachmentBackfillRequestSyncMessage: OutgoingSyncMessage {
    override class var supportsSecureCoding: Bool { true }

    /// A serialized ``SSKProtoSyncMessageAttachmentBackfillRequest``.
    private let serializedRequestProto: Data

    init(
        requestProto: SSKProtoSyncMessageAttachmentBackfillRequest,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) throws {
        serializedRequestProto = try requestProto.serializedData()
        super.init(localThread: localThread, tx: tx)
    }

    // MARK: -

    override var isUrgent: Bool { true }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let builder = SSKProtoSyncMessage.builder()

        do {
            let requestProto = try SSKProtoSyncMessageAttachmentBackfillRequest(
                serializedData: serializedRequestProto,
            )
            builder.setAttachmentBackfillRequest(requestProto)
        } catch {
            owsFailDebug("Failed to deserialize attachment backfill request proto! \(error)")
            return nil
        }

        return builder
    }

    // MARK: -

    required init?(coder: NSCoder) {
        guard
            let serializedRequestProto = coder.decodeObject(
                of: NSData.self,
                forKey: "serializedRequestProto",
            ) as Data?
        else {
            return nil
        }

        self.serializedRequestProto = serializedRequestProto
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(serializedRequestProto, forKey: "serializedRequestProto")
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(serializedRequestProto)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.serializedRequestProto == object.serializedRequestProto else { return false }
        return true
    }
}
