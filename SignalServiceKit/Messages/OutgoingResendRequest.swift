//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc(OWSOutgoingResendRequest)
final class OutgoingResendRequest: TSOutgoingMessage {
    private(set) var decryptionErrorData: Data = Data()
    private(set) var failedEnvelopeGroupId: Data?

    init(
        errorMessageBytes: Data,
        sourceAci: Aci,
        failedEnvelopeGroupId: Data?,
        tx: DBWriteTransaction,
    ) {
        self.decryptionErrorData = errorMessageBytes
        self.failedEnvelopeGroupId = failedEnvelopeGroupId

        let sender = SignalServiceAddress(sourceAci)
        let thread = TSContactThread.getOrCreateThread(withContactAddress: sender, transaction: tx)
        let builder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)

        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(decryptionErrorData, forKey: "decryptionErrorData")
        if let failedEnvelopeGroupId {
            coder.encode(failedEnvelopeGroupId, forKey: "failedEnvelopeGroupId")
        }
    }

    required init?(coder: NSCoder) {
        self.decryptionErrorData = coder.decodeObject(of: NSData.self, forKey: "decryptionErrorData") as Data? ?? Data()
        self.failedEnvelopeGroupId = coder.decodeObject(of: NSData.self, forKey: "failedEnvelopeGroupId") as Data?
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.decryptionErrorData)
        hasher.combine(self.failedEnvelopeGroupId)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.decryptionErrorData == object.decryptionErrorData else { return false }
        guard self.failedEnvelopeGroupId == object.failedEnvelopeGroupId else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.decryptionErrorData = self.decryptionErrorData
        result.failedEnvelopeGroupId = self.failedEnvelopeGroupId
        return result
    }

    override var encryptionStyle: EncryptionStyle { .plaintext }

    override var isUrgent: Bool { false }

    override var shouldRecordSendLog: Bool {
        /// We have to return NO since our preferred style is Plaintext. If we
        /// returned YES, a future resend response would encrypt since MessageSender
        /// only deals with plaintext as Data. This is fine since its contentHint is
        /// `default` anyway. TODO: Maybe we should explore having a first class
        /// type to represent the plaintext message content mid-send? That way we
        /// don't need to call back to the original TSOutgoingMessage for questions
        /// about the plaintext. This makes sense in a world where the
        /// TSOutgoingMessage is divorced from the constructed plaintext because of
        /// the MessageSendLog and OWSOutgoingResendResponse
        return false
    }

    override func shouldSyncTranscript() -> Bool { false }

    override var shouldBeSaved: Bool { false }

    override var contentHint: SealedSenderContentHint { .default }

    override func envelopeGroupIdWithTransaction(_ transaction: DBReadTransaction) -> Data? {
        return self.failedEnvelopeGroupId
    }

    override func buildPlainTextData(_ thread: TSThread, transaction: DBWriteTransaction) -> Data? {
        do {
            let decryptionErrorMessage = try DecryptionErrorMessage(bytes: decryptionErrorData)
            let plaintextContent = PlaintextContent(decryptionErrorMessage)
            return plaintextContent.serialize()
        } catch {
            owsFailDebug("Failed to build plaintext: \(error)")
            return nil
        }
    }
}
