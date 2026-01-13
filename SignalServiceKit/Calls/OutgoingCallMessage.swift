//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// A message sent to the other participants in a call to pass along a RingRTC
/// payload out-of-band.
///
/// Not to be confused with a ``TSCall``.
public final class OutgoingCallMessage: TSOutgoingMessage {
    public enum MessageType: Hashable {
        case offerMessage(SSKProtoCallMessageOffer)
        case answerMessage(SSKProtoCallMessageAnswer)
        case iceUpdateMessages([SSKProtoCallMessageIceUpdate])
        case hangupMessage(SSKProtoCallMessageHangup)
        case busyMessage(SSKProtoCallMessageBusy)
        case opaqueMessage(SSKProtoCallMessageOpaque)
    }

    private(set) var messageType: MessageType!
    private(set) var destinationDeviceId: UInt32?

    public init(
        thread: TSThread,
        messageType: MessageType,
        destinationDeviceId: UInt32? = nil,
        overrideRecipients: [Aci] = [],
        tx: DBReadTransaction,
    ) {
        self.messageType = messageType
        self.destinationDeviceId = destinationDeviceId
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: overrideRecipients.map(AciObjC.init(_:)),
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    public required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.messageType)
        hasher.combine(self.destinationDeviceId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.messageType == object.messageType else { return false }
        guard self.destinationDeviceId == object.destinationDeviceId else { return false }
        return true
    }

    override public func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.messageType = self.messageType
        result.destinationDeviceId = self.destinationDeviceId
        return result
    }

    override public func shouldSyncTranscript() -> Bool { false }

    override public func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        let builder = SSKProtoCallMessage.builder()

        var shouldHaveProfileKey = false

        switch messageType {
        case .offerMessage(let offerMessage):
            builder.setOffer(offerMessage)
            shouldHaveProfileKey = true
        case .answerMessage(let answerMessage):
            builder.setAnswer(answerMessage)
            shouldHaveProfileKey = true
        case .iceUpdateMessages(let iceUpdateMessages):
            builder.setIceUpdate(iceUpdateMessages)
        case .hangupMessage(let hangupMessage):
            builder.setHangup(hangupMessage)
        case .busyMessage(let busyMessage):
            builder.setBusy(busyMessage)
        case .opaqueMessage(let opaqueMessage):
            builder.setOpaque(opaqueMessage)
        case nil:
            owsFailDebug("must have type for call message")
            return nil
        }

        if let destinationDeviceId {
            builder.setDestinationDeviceID(destinationDeviceId)
        }

        if shouldHaveProfileKey {
            ProtoUtils.addLocalProfileKeyIfNecessary(thread, callMessageBuilder: builder, transaction: transaction)
        }

        do {
            let contentBuilder = SSKProtoContent.builder()
            contentBuilder.setCallMessage(try builder.build())
            return contentBuilder
        } catch {
            owsFailDebug("couldn't build call message: \(error)")
            return nil
        }
    }

    override public var shouldBeSaved: Bool { false }

    override public var isUrgent: Bool {
        switch self.messageType {
        case .offerMessage:
            return true
        case .opaqueMessage(let opaqueMessage):
            switch opaqueMessage.urgency {
            case .handleImmediately:
                return true
            case .droppable, nil:
                break
            }
        default:
            break
        }
        return false
    }

    override public var debugDescription: String {
        let payloadType: String
        switch messageType {
        case .offerMessage:
            payloadType = "offerMessage"
        case .answerMessage:
            payloadType = "answerMessage"
        case .iceUpdateMessages(let iceUpdateMessages):
            payloadType = "iceUpdateMessages: \(iceUpdateMessages.count)"
        case .hangupMessage:
            payloadType = "hangupMessage"
        case .busyMessage:
            payloadType = "busyMessage"
        case .opaqueMessage:
            payloadType = "opaqueMessage"
        case nil:
            payloadType = "nil"
        }
        return "\(type(of: self)) with payload: \(payloadType)"
    }

    override public var shouldRecordSendLog: Bool { false }

    override public var contentHint: SealedSenderContentHint { .default }
}
