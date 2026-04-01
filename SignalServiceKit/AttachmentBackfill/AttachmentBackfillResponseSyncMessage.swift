//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - AttachmentBackfillResponseSyncMessage

@objc(AttachmentBackfillResponseSyncMessage)
final class AttachmentBackfillResponseSyncMessage: OutgoingSyncMessage {
    override class var supportsSecureCoding: Bool { true }

    let responseProto: SSKProtoSyncMessageAttachmentBackfillResponse
    private let serializedResponseProto: Data

    init(
        responseProto: SSKProtoSyncMessageAttachmentBackfillResponse,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) throws {
        self.responseProto = responseProto
        self.serializedResponseProto = try responseProto.serializedData()
        super.init(localThread: localThread, tx: tx)
    }

    // MARK: -

    override var isUrgent: Bool { true }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let builder = SSKProtoSyncMessage.builder()
        builder.setAttachmentBackfillResponse(responseProto)
        return builder
    }

    // MARK: -

    required init?(coder: NSCoder) {
        guard
            let serializedResponseProto = coder.decodeObject(
                of: NSData.self,
                forKey: "serializedResponseProto",
            ) as Data?,
            let responseProto = try? SSKProtoSyncMessageAttachmentBackfillResponse(
                serializedData: serializedResponseProto,
            )
        else {
            return nil
        }

        self.responseProto = responseProto
        self.serializedResponseProto = serializedResponseProto
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(serializedResponseProto, forKey: "serializedResponseProto")
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(serializedResponseProto)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.serializedResponseProto == object.serializedResponseProto else { return false }
        return true
    }
}
