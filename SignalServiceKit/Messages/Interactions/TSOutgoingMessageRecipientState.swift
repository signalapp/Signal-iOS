//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc(TSOutgoingMessageRecipientState)
public final class TSOutgoingMessageRecipientState: NSObject, NSCoding, NSCopying {
    /// The status of the outgoing message send to this recipient.
    public private(set) var status: OWSOutgoingMessageRecipientStatus

    /// Represents the time at which `status` was last updated.
    ///
    /// - Important
    /// This may be a locally-generated timestamp for `status` cases that refer
    /// to local state, or a remote timestamp for `status` cases that refer to
    /// to remote state.
    ///
    /// For example, `status: .sending` will contain a  locally-generated
    /// timestamp, but `status: .read` will contain a timestamp pulled from a
    /// read receipt. `status: .sent` may contain a local timestamp for
    /// messages sent on this device, or a timestamp pulled from a sent message
    /// transcript for messages sent on a linked device.
    ///
    /// - Note
    /// May be 0 for legacy recipient states depending on `status`. Legacy
    /// recipient states only tracked a timestamp for `status` values of
    /// `.delivered`, `.read.`, and `.viewed`.
    public private(set) var statusTimestamp: UInt64

    /// Whether the send used unidentified delivery, aka Sealed Sender.
    ///
    /// - Note
    /// This is always `false` until a send has been completed.
    public var wasSentByUD: Bool

    /// Represents an error that occurred during sending. Will only be present
    /// if `canHaveErrorCode` is true.
    public var errorCode: Int?

    /// If true, this state supports errors. If false, it doesn't. The
    /// `.sending` and `.pending` states may have transient failures that
    /// haven't yet become terminal failures.
    var canHaveErrorCode: Bool {
        switch self.status {
        case .sending, .pending, .failed:
            return true
        case .skipped, .sent, .delivered, .read, .viewed:
            return false
        }
    }

    @objc
    public convenience init(status: OWSOutgoingMessageRecipientStatus) {
        self.init(
            status: status,
            statusTimestamp: Date().ows_millisecondsSince1970,
            wasSentByUD: false,
            errorCode: nil,
        )
    }

    public init(
        status: OWSOutgoingMessageRecipientStatus,
        statusTimestamp: UInt64,
        wasSentByUD: Bool,
        errorCode: Int?,
    ) {
        self.status = status
        self.statusTimestamp = statusTimestamp
        self.wasSentByUD = wasSentByUD
        self.errorCode = errorCode

        super.init()
    }

    func updateStatusIfPossible(
        _ newStatus: OWSOutgoingMessageRecipientStatus,
        statusTimestamp: UInt64 = Date().ows_millisecondsSince1970,
    ) {
        if newStatus.priorityValue < self.status.priorityValue {
            Logger.warn("Ignoring status update to '\(newStatus)' that would move backwards from '\(self.status)'")
            return
        }
        self.status = newStatus
        self.statusTimestamp = statusTimestamp
        if !self.canHaveErrorCode {
            self.errorCode = nil
        }
    }

    // MARK: - NSCoding

    fileprivate enum CoderKeys: String {
        case status = "state"
        case wasSentByUD
        case statusTimestamp
        case errorCode
    }

    public required init?(coder: NSCoder) {
        guard
            let statusRawValue = coder.decodeObject(of: NSNumber.self, forCoderKey: .status) as? UInt,
            let status = OWSOutgoingMessageRecipientStatus(rawValue: statusRawValue)
        else {
            owsFailDebug("Missing or unrecognized fields!")
            return nil
        }

        if let statusTimestamp = coder.decodeObject(of: NSNumber.self, forCoderKey: .statusTimestamp) {
            self.status = status
            self.statusTimestamp = statusTimestamp.uint64Value
        } else {
            /// Legacy recipient states represented "delivered", "read", and
            /// "viewed" by setting `status = .sent` and storing a dedicated
            /// timestamp for each of those states. We use the presence of those
            /// dedicated timestamps to migrate the legacy states to the current
            /// representation, which uses more precise `status` cases along with a
            /// general `statusTimestamp`.
            if let viewedTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "viewedTimestamp") {
                owsAssertDebug(status == .sent)
                self.status = .viewed
                self.statusTimestamp = viewedTimestamp.uint64Value
            } else if let readTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "readTimestamp") {
                owsAssertDebug(status == .sent)
                self.status = .read
                self.statusTimestamp = readTimestamp.uint64Value
            } else if let deliveryTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "deliveryTimestamp") {
                owsAssertDebug(status == .sent)
                self.status = .delivered
                self.statusTimestamp = deliveryTimestamp.uint64Value
            } else {
                self.status = status
                self.statusTimestamp = 0
            }
        }

        if let wasSentByUD = coder.decodeObject(of: NSNumber.self, forCoderKey: .wasSentByUD) as? Bool {
            self.wasSentByUD = wasSentByUD
        } else {
            /// Truly old recipient states may not have had this property
            /// serialized, so we'll default to `false` to match the zero-value
            /// it would've gotten when deserialized.
            self.wasSentByUD = false
        }

        self.errorCode = coder.decodeObject(of: NSNumber.self, forCoderKey: .errorCode)?.intValue
    }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: status.rawValue), forCoderKey: .status)
        coder.encode(NSNumber(value: statusTimestamp), forCoderKey: .statusTimestamp)
        coder.encode(NSNumber(booleanLiteral: wasSentByUD), forCoderKey: .wasSentByUD)
        if let errorCode {
            coder.encode(NSNumber(value: errorCode), forCoderKey: .errorCode)
        }
    }

    // MARK: - NSCopying

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            status: status,
            statusTimestamp: statusTimestamp,
            wasSentByUD: wasSentByUD,
            errorCode: errorCode,
        )
    }
}

// MARK: -

private extension NSCoder {
    func decodeObject<DecodedObjectType: NSObject & NSCoding>(
        of cls: DecodedObjectType.Type,
        forCoderKey key: TSOutgoingMessageRecipientState.CoderKeys,
    ) -> DecodedObjectType? {
        return decodeObject(of: cls, forKey: key.rawValue)
    }

    func encode<EncodedObjectType: NSObject & NSCoding>(
        _ object: EncodedObjectType,
        forCoderKey key: TSOutgoingMessageRecipientState.CoderKeys,
    ) {
        encode(object, forKey: key.rawValue)
    }
}

// MARK: -

@objc
public enum OWSOutgoingMessageRecipientStatus: UInt, CustomDebugStringConvertible {
    /// The message could not be sent to this recipient.
    case failed = 0
    /// The message is being sent (enqueued, uploading) to this recipient.
    case sending = 1
    /// The message was not sent to this recipient because they are invalid or
    /// have already received the message via another channel. For example, the
    /// same recipient may be on multiple story distribution lists, or may have
    /// left a group we are sending to.
    case skipped = 2
    /// The message has been sent to the service.
    case sent = 3
    /// The message has been delivered to this recipient.
    case delivered = 5
    /// The message has been read by the recipient.
    case read = 6
    /// The message has been viewed by the recipient. This only applies to
    /// messages that are "viewed" explicitly, such as view-once media and voice
    /// messages.
    case viewed = 7
    /// The message was rejected by the server until some other condition is
    /// satisfied. For example, the message send may be pending a CAPTCHA.
    case pending = 4

    /// A "priority" for a given status.
    ///
    /// We can never move from a higher priority to a lower priority.
    ///
    /// For example, once we've received a delivery receipt for a message, we
    /// can never mark it as "sent". If we have a delivery receipt, that implies
    /// that it was sent, and if we mark it as "sent", we'd lose information
    /// indicating that it was delivered.
    var priorityValue: Int {
        switch self {
        case .sending, .pending, .failed:
            // We swap freely amongst these values as we send messages.
            return 1
        case .skipped:
            // If we try to "skip" a message that was already "sent", it should remain
            // "sent" because we *did* send it.
            return 2
        case .sent:
            return 3
        case .delivered:
            return 4
        case .read:
            return 5
        case .viewed:
            return 6
        }
    }

    public var debugDescription: String {
        switch self {
        case .failed: "failed"
        case .sending: "sending"
        case .skipped: "skipped"
        case .sent: "sent"
        case .delivered: "delivered"
        case .read: "read"
        case .viewed: "viewed"
        case .pending: "pending"
        }
    }
}

/// This type is `Codable`-serialized by `StoryMessage`.
extension OWSOutgoingMessageRecipientStatus: Codable {}
