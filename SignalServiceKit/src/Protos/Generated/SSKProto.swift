//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum SSKProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SSKProtoEnvelope

@objc public class SSKProtoEnvelope: NSObject {

	// MARK: - SSKProtoEnvelopeType

	@objc public enum SSKProtoEnvelopeType: Int32 {
		case unknown = 0
		case ciphertext = 1
		case keyExchange = 2
		case prekeyBundle = 3
		case receipt = 5
	}

	private class func SSKProtoEnvelopeTypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelopeType {
		switch value {
		case .unknown: return .unknown
		case .ciphertext: return .ciphertext
		case .keyExchange: return .keyExchange
		case .prekeyBundle: return .prekeyBundle
		case .receipt: return .receipt
		}
	}

	private class func SSKProtoEnvelopeTypeUnwrap(_ value: SSKProtoEnvelopeType) -> SignalServiceProtos_Envelope.TypeEnum {
		switch value {
		case .unknown: return .unknown
		case .ciphertext: return .ciphertext
		case .keyExchange: return .keyExchange
		case .prekeyBundle: return .prekeyBundle
		case .receipt: return .receipt
		}
	}

	@objc public let type: SSKProtoEnvelopeType
	@objc public let source: String?
	@objc public let sourceDevice: UInt32
	@objc public let relay: String?
	@objc public let timestamp: UInt64
	@objc public let legacyMessage: Data?
	@objc public let content: Data?

	@objc public init(type: SSKProtoEnvelopeType,
	                  source: String?,
	                  sourceDevice: UInt32,
	                  relay: String?,
	                  timestamp: UInt64,
	                  legacyMessage: Data?,
	                  content: Data?) {
		self.type = type
		self.source = source
		self.sourceDevice = sourceDevice
		self.relay = relay
		self.timestamp = timestamp
		self.legacyMessage = legacyMessage
		self.content = content
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoEnvelope {
		let proto = try SignalServiceProtos_Envelope(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_Envelope) throws -> SSKProtoEnvelope {
		var type: SSKProtoEnvelopeType = .unknown
		if proto.hasType {
			type = SSKProtoEnvelopeTypeWrap(proto.type)
		}

		var source: String? = nil
		if proto.hasSource {
			source = proto.source
		}

		var sourceDevice: UInt32 = 0
		if proto.hasSourceDevice {
			sourceDevice = proto.sourceDevice
		}

		var relay: String? = nil
		if proto.hasRelay {
			relay = proto.relay
		}

		var timestamp: UInt64 = 0
		if proto.hasTimestamp {
			timestamp = proto.timestamp
		}

		var legacyMessage: Data? = nil
		if proto.hasLegacyMessage {
			legacyMessage = proto.legacyMessage
		}

		var content: Data? = nil
		if proto.hasContent {
			content = proto.content
		}

		// MARK: - Begin Validation Logic for SSKProtoEnvelope -

        guard proto.hasSource else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: source")
        }
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }
        guard proto.hasSourceDevice else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sourceDevice")
        }

		// MARK: - End Validation Logic for SSKProtoEnvelope -

		let result = SSKProtoEnvelope(type: type,
		                              source: source,
		                              sourceDevice: sourceDevice,
		                              relay: relay,
		                              timestamp: timestamp,
		                              legacyMessage: legacyMessage,
		                              content: content)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_Envelope {
		let proto = SignalServiceProtos_Envelope.with { (builder) in
			builder.type = SSKProtoEnvelope.SSKProtoEnvelopeTypeUnwrap(self.type)

			if let source = self.source {
				builder.source = source
			}

			builder.sourceDevice = self.sourceDevice

			if let relay = self.relay {
				builder.relay = relay
			}

			builder.timestamp = self.timestamp

			if let legacyMessage = self.legacyMessage {
				builder.legacyMessage = legacyMessage
			}

			if let content = self.content {
				builder.content = content
			}
		}

		return proto
	}
}

// MARK: - SSKProtoContent

@objc public class SSKProtoContent: NSObject {

	@objc public let dataMessage: SSKProtoDataMessage?
	@objc public let syncMessage: SSKProtoSyncMessage?
	@objc public let callMessage: SSKProtoCallMessage?
	@objc public let nullMessage: SSKProtoNullMessage?
	@objc public let receiptMessage: SSKProtoReceiptMessage?

	@objc public init(dataMessage: SSKProtoDataMessage?,
	                  syncMessage: SSKProtoSyncMessage?,
	                  callMessage: SSKProtoCallMessage?,
	                  nullMessage: SSKProtoNullMessage?,
	                  receiptMessage: SSKProtoReceiptMessage?) {
		self.dataMessage = dataMessage
		self.syncMessage = syncMessage
		self.callMessage = callMessage
		self.nullMessage = nullMessage
		self.receiptMessage = receiptMessage
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContent {
		let proto = try SignalServiceProtos_Content(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_Content) throws -> SSKProtoContent {
		var dataMessage: SSKProtoDataMessage? = nil
		if proto.hasDataMessage {
			dataMessage = try SSKProtoDataMessage.parseProto(proto.dataMessage)
		}

		var syncMessage: SSKProtoSyncMessage? = nil
		if proto.hasSyncMessage {
			syncMessage = try SSKProtoSyncMessage.parseProto(proto.syncMessage)
		}

		var callMessage: SSKProtoCallMessage? = nil
		if proto.hasCallMessage {
			callMessage = try SSKProtoCallMessage.parseProto(proto.callMessage)
		}

		var nullMessage: SSKProtoNullMessage? = nil
		if proto.hasNullMessage {
			nullMessage = try SSKProtoNullMessage.parseProto(proto.nullMessage)
		}

		var receiptMessage: SSKProtoReceiptMessage? = nil
		if proto.hasReceiptMessage {
			receiptMessage = try SSKProtoReceiptMessage.parseProto(proto.receiptMessage)
		}

		// MARK: - Begin Validation Logic for SSKProtoContent -

		// MARK: - End Validation Logic for SSKProtoContent -

		let result = SSKProtoContent(dataMessage: dataMessage,
		                             syncMessage: syncMessage,
		                             callMessage: callMessage,
		                             nullMessage: nullMessage,
		                             receiptMessage: receiptMessage)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_Content {
		let proto = SignalServiceProtos_Content.with { (builder) in
			if let dataMessage = self.dataMessage {
				builder.dataMessage = dataMessage.asProtobuf
			}

			if let syncMessage = self.syncMessage {
				builder.syncMessage = syncMessage.asProtobuf
			}

			if let callMessage = self.callMessage {
				builder.callMessage = callMessage.asProtobuf
			}

			if let nullMessage = self.nullMessage {
				builder.nullMessage = nullMessage.asProtobuf
			}

			if let receiptMessage = self.receiptMessage {
				builder.receiptMessage = receiptMessage.asProtobuf
			}
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessageOffer

@objc public class SSKProtoCallMessageOffer: NSObject {

	@objc public let id: UInt64
	@objc public let sessionDescription: String?

	@objc public init(id: UInt64,
	                  sessionDescription: String?) {
		self.id = id
		self.sessionDescription = sessionDescription
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageOffer {
		let proto = try SignalServiceProtos_CallMessage.Offer(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Offer) throws -> SSKProtoCallMessageOffer {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		var sessionDescription: String? = nil
		if proto.hasSessionDescription {
			sessionDescription = proto.sessionDescription
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessageOffer -

		// MARK: - End Validation Logic for SSKProtoCallMessageOffer -

		let result = SSKProtoCallMessageOffer(id: id,
		                                      sessionDescription: sessionDescription)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Offer {
		let proto = SignalServiceProtos_CallMessage.Offer.with { (builder) in
			builder.id = self.id

			if let sessionDescription = self.sessionDescription {
				builder.sessionDescription = sessionDescription
			}
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessageAnswer

@objc public class SSKProtoCallMessageAnswer: NSObject {

	@objc public let id: UInt64
	@objc public let sessionDescription: String?

	@objc public init(id: UInt64,
	                  sessionDescription: String?) {
		self.id = id
		self.sessionDescription = sessionDescription
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageAnswer {
		let proto = try SignalServiceProtos_CallMessage.Answer(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Answer) throws -> SSKProtoCallMessageAnswer {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		var sessionDescription: String? = nil
		if proto.hasSessionDescription {
			sessionDescription = proto.sessionDescription
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessageAnswer -

		// MARK: - End Validation Logic for SSKProtoCallMessageAnswer -

		let result = SSKProtoCallMessageAnswer(id: id,
		                                       sessionDescription: sessionDescription)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Answer {
		let proto = SignalServiceProtos_CallMessage.Answer.with { (builder) in
			builder.id = self.id

			if let sessionDescription = self.sessionDescription {
				builder.sessionDescription = sessionDescription
			}
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessageIceUpdate

@objc public class SSKProtoCallMessageIceUpdate: NSObject {

	@objc public let id: UInt64
	@objc public let sdpMid: String?
	@objc public let sdpMlineIndex: UInt32
	@objc public let sdp: String?

	@objc public init(id: UInt64,
	                  sdpMid: String?,
	                  sdpMlineIndex: UInt32,
	                  sdp: String?) {
		self.id = id
		self.sdpMid = sdpMid
		self.sdpMlineIndex = sdpMlineIndex
		self.sdp = sdp
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageIceUpdate {
		let proto = try SignalServiceProtos_CallMessage.IceUpdate(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.IceUpdate) throws -> SSKProtoCallMessageIceUpdate {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		var sdpMid: String? = nil
		if proto.hasSdpMid {
			sdpMid = proto.sdpMid
		}

		var sdpMlineIndex: UInt32 = 0
		if proto.hasSdpMlineIndex {
			sdpMlineIndex = proto.sdpMlineIndex
		}

		var sdp: String? = nil
		if proto.hasSdp {
			sdp = proto.sdp
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessageIceUpdate -

		// MARK: - End Validation Logic for SSKProtoCallMessageIceUpdate -

		let result = SSKProtoCallMessageIceUpdate(id: id,
		                                          sdpMid: sdpMid,
		                                          sdpMlineIndex: sdpMlineIndex,
		                                          sdp: sdp)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage.IceUpdate {
		let proto = SignalServiceProtos_CallMessage.IceUpdate.with { (builder) in
			builder.id = self.id

			if let sdpMid = self.sdpMid {
				builder.sdpMid = sdpMid
			}

			builder.sdpMlineIndex = self.sdpMlineIndex

			if let sdp = self.sdp {
				builder.sdp = sdp
			}
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessageBusy

@objc public class SSKProtoCallMessageBusy: NSObject {

	@objc public let id: UInt64

	@objc public init(id: UInt64) {
		self.id = id
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageBusy {
		let proto = try SignalServiceProtos_CallMessage.Busy(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Busy) throws -> SSKProtoCallMessageBusy {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessageBusy -

		// MARK: - End Validation Logic for SSKProtoCallMessageBusy -

		let result = SSKProtoCallMessageBusy(id: id)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Busy {
		let proto = SignalServiceProtos_CallMessage.Busy.with { (builder) in
			builder.id = self.id
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessageHangup

@objc public class SSKProtoCallMessageHangup: NSObject {

	@objc public let id: UInt64

	@objc public init(id: UInt64) {
		self.id = id
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessageHangup {
		let proto = try SignalServiceProtos_CallMessage.Hangup(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage.Hangup) throws -> SSKProtoCallMessageHangup {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessageHangup -

		// MARK: - End Validation Logic for SSKProtoCallMessageHangup -

		let result = SSKProtoCallMessageHangup(id: id)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Hangup {
		let proto = SignalServiceProtos_CallMessage.Hangup.with { (builder) in
			builder.id = self.id
		}

		return proto
	}
}

// MARK: - SSKProtoCallMessage

@objc public class SSKProtoCallMessage: NSObject {

	@objc public let offer: SSKProtoCallMessageOffer?
	@objc public let answer: SSKProtoCallMessageAnswer?
	@objc public let iceUpdate: [SSKProtoCallMessageIceUpdate]
	@objc public let hangup: SSKProtoCallMessageHangup?
	@objc public let busy: SSKProtoCallMessageBusy?
	@objc public let profileKey: Data?

	@objc public init(offer: SSKProtoCallMessageOffer?,
	                  answer: SSKProtoCallMessageAnswer?,
	                  iceUpdate: [SSKProtoCallMessageIceUpdate],
	                  hangup: SSKProtoCallMessageHangup?,
	                  busy: SSKProtoCallMessageBusy?,
	                  profileKey: Data?) {
		self.offer = offer
		self.answer = answer
		self.iceUpdate = iceUpdate
		self.hangup = hangup
		self.busy = busy
		self.profileKey = profileKey
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoCallMessage {
		let proto = try SignalServiceProtos_CallMessage(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_CallMessage) throws -> SSKProtoCallMessage {
		var offer: SSKProtoCallMessageOffer? = nil
		if proto.hasOffer {
			offer = try SSKProtoCallMessageOffer.parseProto(proto.offer)
		}

		var answer: SSKProtoCallMessageAnswer? = nil
		if proto.hasAnswer {
			answer = try SSKProtoCallMessageAnswer.parseProto(proto.answer)
		}

		var iceUpdate: [SSKProtoCallMessageIceUpdate] = []
		for item in proto.iceUpdate {
			let wrapped = try SSKProtoCallMessageIceUpdate.parseProto(item)
			iceUpdate.append(wrapped)
		}

		var hangup: SSKProtoCallMessageHangup? = nil
		if proto.hasHangup {
			hangup = try SSKProtoCallMessageHangup.parseProto(proto.hangup)
		}

		var busy: SSKProtoCallMessageBusy? = nil
		if proto.hasBusy {
			busy = try SSKProtoCallMessageBusy.parseProto(proto.busy)
		}

		var profileKey: Data? = nil
		if proto.hasProfileKey {
			profileKey = proto.profileKey
		}

		// MARK: - Begin Validation Logic for SSKProtoCallMessage -

		// MARK: - End Validation Logic for SSKProtoCallMessage -

		let result = SSKProtoCallMessage(offer: offer,
		                                 answer: answer,
		                                 iceUpdate: iceUpdate,
		                                 hangup: hangup,
		                                 busy: busy,
		                                 profileKey: profileKey)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage {
		let proto = SignalServiceProtos_CallMessage.with { (builder) in
			if let offer = self.offer {
				builder.offer = offer.asProtobuf
			}

			if let answer = self.answer {
				builder.answer = answer.asProtobuf
			}

			var iceUpdateUnwrapped = [SignalServiceProtos_CallMessage.IceUpdate]()
			for item in iceUpdate {
				iceUpdateUnwrapped.append(item.asProtobuf)
			}
			builder.iceUpdate = iceUpdateUnwrapped

			if let hangup = self.hangup {
				builder.hangup = hangup.asProtobuf
			}

			if let busy = self.busy {
				builder.busy = busy.asProtobuf
			}

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageQuoteQuotedAttachment

@objc public class SSKProtoDataMessageQuoteQuotedAttachment: NSObject {

	// MARK: - SSKProtoDataMessageQuoteQuotedAttachmentFlags

	@objc public enum SSKProtoDataMessageQuoteQuotedAttachmentFlags: Int32 {
		case voiceMessage = 1
	}

	private class func SSKProtoDataMessageQuoteQuotedAttachmentFlagsWrap(_ value: SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags) -> SSKProtoDataMessageQuoteQuotedAttachmentFlags {
		switch value {
		case .voiceMessage: return .voiceMessage
		}
	}

	private class func SSKProtoDataMessageQuoteQuotedAttachmentFlagsUnwrap(_ value: SSKProtoDataMessageQuoteQuotedAttachmentFlags) -> SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags {
		switch value {
		case .voiceMessage: return .voiceMessage
		}
	}

	@objc public let contentType: String?
	@objc public let fileName: String?
	@objc public let thumbnail: SSKProtoAttachmentPointer?
	@objc public let flags: UInt32

	@objc public init(contentType: String?,
	                  fileName: String?,
	                  thumbnail: SSKProtoAttachmentPointer?,
	                  flags: UInt32) {
		self.contentType = contentType
		self.fileName = fileName
		self.thumbnail = thumbnail
		self.flags = flags
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
		let proto = try SignalServiceProtos_DataMessage.Quote.QuotedAttachment(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Quote.QuotedAttachment) throws -> SSKProtoDataMessageQuoteQuotedAttachment {
		var contentType: String? = nil
		if proto.hasContentType {
			contentType = proto.contentType
		}

		var fileName: String? = nil
		if proto.hasFileName {
			fileName = proto.fileName
		}

		var thumbnail: SSKProtoAttachmentPointer? = nil
		if proto.hasThumbnail {
			thumbnail = try SSKProtoAttachmentPointer.parseProto(proto.thumbnail)
		}

		var flags: UInt32 = 0
		if proto.hasFlags {
			flags = proto.flags
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

		// MARK: - End Validation Logic for SSKProtoDataMessageQuoteQuotedAttachment -

		let result = SSKProtoDataMessageQuoteQuotedAttachment(contentType: contentType,
		                                                      fileName: fileName,
		                                                      thumbnail: thumbnail,
		                                                      flags: flags)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote.QuotedAttachment {
		let proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment.with { (builder) in
			if let contentType = self.contentType {
				builder.contentType = contentType
			}

			if let fileName = self.fileName {
				builder.fileName = fileName
			}

			if let thumbnail = self.thumbnail {
				builder.thumbnail = thumbnail.asProtobuf
			}

			builder.flags = self.flags
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageQuote

@objc public class SSKProtoDataMessageQuote: NSObject {

	@objc public let id: UInt64
	@objc public let author: String?
	@objc public let text: String?
	@objc public let attachments: [SSKProtoDataMessageQuoteQuotedAttachment]

	@objc public init(id: UInt64,
	                  author: String?,
	                  text: String?,
	                  attachments: [SSKProtoDataMessageQuoteQuotedAttachment]) {
		self.id = id
		self.author = author
		self.text = text
		self.attachments = attachments
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageQuote {
		let proto = try SignalServiceProtos_DataMessage.Quote(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Quote) throws -> SSKProtoDataMessageQuote {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		var author: String? = nil
		if proto.hasAuthor {
			author = proto.author
		}

		var text: String? = nil
		if proto.hasText {
			text = proto.text
		}

		var attachments: [SSKProtoDataMessageQuoteQuotedAttachment] = []
		for item in proto.attachments {
			let wrapped = try SSKProtoDataMessageQuoteQuotedAttachment.parseProto(item)
			attachments.append(wrapped)
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageQuote -

		// MARK: - End Validation Logic for SSKProtoDataMessageQuote -

		let result = SSKProtoDataMessageQuote(id: id,
		                                      author: author,
		                                      text: text,
		                                      attachments: attachments)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote {
		let proto = SignalServiceProtos_DataMessage.Quote.with { (builder) in
			builder.id = self.id

			if let author = self.author {
				builder.author = author
			}

			if let text = self.text {
				builder.text = text
			}

			var attachmentsUnwrapped = [SignalServiceProtos_DataMessage.Quote.QuotedAttachment]()
			for item in attachments {
				attachmentsUnwrapped.append(item.asProtobuf)
			}
			builder.attachments = attachmentsUnwrapped
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContactName

@objc public class SSKProtoDataMessageContactName: NSObject {

	@objc public let givenName: String?
	@objc public let familyName: String?
	@objc public let prefix: String?
	@objc public let suffix: String?
	@objc public let middleName: String?
	@objc public let displayName: String?

	@objc public init(givenName: String?,
	                  familyName: String?,
	                  prefix: String?,
	                  suffix: String?,
	                  middleName: String?,
	                  displayName: String?) {
		self.givenName = givenName
		self.familyName = familyName
		self.prefix = prefix
		self.suffix = suffix
		self.middleName = middleName
		self.displayName = displayName
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactName {
		let proto = try SignalServiceProtos_DataMessage.Contact.Name(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Name) throws -> SSKProtoDataMessageContactName {
		var givenName: String? = nil
		if proto.hasGivenName {
			givenName = proto.givenName
		}

		var familyName: String? = nil
		if proto.hasFamilyName {
			familyName = proto.familyName
		}

		var prefix: String? = nil
		if proto.hasPrefix {
			prefix = proto.prefix
		}

		var suffix: String? = nil
		if proto.hasSuffix {
			suffix = proto.suffix
		}

		var middleName: String? = nil
		if proto.hasMiddleName {
			middleName = proto.middleName
		}

		var displayName: String? = nil
		if proto.hasDisplayName {
			displayName = proto.displayName
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContactName -

		// MARK: - End Validation Logic for SSKProtoDataMessageContactName -

		let result = SSKProtoDataMessageContactName(givenName: givenName,
		                                            familyName: familyName,
		                                            prefix: prefix,
		                                            suffix: suffix,
		                                            middleName: middleName,
		                                            displayName: displayName)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Name {
		let proto = SignalServiceProtos_DataMessage.Contact.Name.with { (builder) in
			if let givenName = self.givenName {
				builder.givenName = givenName
			}

			if let familyName = self.familyName {
				builder.familyName = familyName
			}

			if let prefix = self.prefix {
				builder.prefix = prefix
			}

			if let suffix = self.suffix {
				builder.suffix = suffix
			}

			if let middleName = self.middleName {
				builder.middleName = middleName
			}

			if let displayName = self.displayName {
				builder.displayName = displayName
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContactPhone

@objc public class SSKProtoDataMessageContactPhone: NSObject {

	// MARK: - SSKProtoDataMessageContactPhoneType

	@objc public enum SSKProtoDataMessageContactPhoneType: Int32 {
		case home = 1
		case mobile = 2
		case work = 3
		case custom = 4
	}

	private class func SSKProtoDataMessageContactPhoneTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SSKProtoDataMessageContactPhoneType {
		switch value {
		case .home: return .home
		case .mobile: return .mobile
		case .work: return .work
		case .custom: return .custom
		}
	}

	private class func SSKProtoDataMessageContactPhoneTypeUnwrap(_ value: SSKProtoDataMessageContactPhoneType) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
		switch value {
		case .home: return .home
		case .mobile: return .mobile
		case .work: return .work
		case .custom: return .custom
		}
	}

	@objc public let value: String?
	@objc public let type: SSKProtoDataMessageContactPhoneType
	@objc public let label: String?

	@objc public init(value: String?,
	                  type: SSKProtoDataMessageContactPhoneType,
	                  label: String?) {
		self.value = value
		self.type = type
		self.label = label
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactPhone {
		let proto = try SignalServiceProtos_DataMessage.Contact.Phone(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Phone) throws -> SSKProtoDataMessageContactPhone {
		var value: String? = nil
		if proto.hasValue {
			value = proto.value
		}

		var type: SSKProtoDataMessageContactPhoneType = .home
		if proto.hasType {
			type = SSKProtoDataMessageContactPhoneTypeWrap(proto.type)
		}

		var label: String? = nil
		if proto.hasLabel {
			label = proto.label
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContactPhone -

        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }

		// MARK: - End Validation Logic for SSKProtoDataMessageContactPhone -

		let result = SSKProtoDataMessageContactPhone(value: value,
		                                             type: type,
		                                             label: label)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Phone {
		let proto = SignalServiceProtos_DataMessage.Contact.Phone.with { (builder) in
			if let value = self.value {
				builder.value = value
			}

			builder.type = SSKProtoDataMessageContactPhone.SSKProtoDataMessageContactPhoneTypeUnwrap(self.type)

			if let label = self.label {
				builder.label = label
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContactEmail

@objc public class SSKProtoDataMessageContactEmail: NSObject {

	// MARK: - SSKProtoDataMessageContactEmailType

	@objc public enum SSKProtoDataMessageContactEmailType: Int32 {
		case home = 1
		case mobile = 2
		case work = 3
		case custom = 4
	}

	private class func SSKProtoDataMessageContactEmailTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SSKProtoDataMessageContactEmailType {
		switch value {
		case .home: return .home
		case .mobile: return .mobile
		case .work: return .work
		case .custom: return .custom
		}
	}

	private class func SSKProtoDataMessageContactEmailTypeUnwrap(_ value: SSKProtoDataMessageContactEmailType) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
		switch value {
		case .home: return .home
		case .mobile: return .mobile
		case .work: return .work
		case .custom: return .custom
		}
	}

	@objc public let value: String?
	@objc public let type: SSKProtoDataMessageContactEmailType
	@objc public let label: String?

	@objc public init(value: String?,
	                  type: SSKProtoDataMessageContactEmailType,
	                  label: String?) {
		self.value = value
		self.type = type
		self.label = label
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactEmail {
		let proto = try SignalServiceProtos_DataMessage.Contact.Email(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Email) throws -> SSKProtoDataMessageContactEmail {
		var value: String? = nil
		if proto.hasValue {
			value = proto.value
		}

		var type: SSKProtoDataMessageContactEmailType = .home
		if proto.hasType {
			type = SSKProtoDataMessageContactEmailTypeWrap(proto.type)
		}

		var label: String? = nil
		if proto.hasLabel {
			label = proto.label
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContactEmail -

        guard proto.hasValue else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: value")
        }

		// MARK: - End Validation Logic for SSKProtoDataMessageContactEmail -

		let result = SSKProtoDataMessageContactEmail(value: value,
		                                             type: type,
		                                             label: label)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Email {
		let proto = SignalServiceProtos_DataMessage.Contact.Email.with { (builder) in
			if let value = self.value {
				builder.value = value
			}

			builder.type = SSKProtoDataMessageContactEmail.SSKProtoDataMessageContactEmailTypeUnwrap(self.type)

			if let label = self.label {
				builder.label = label
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContactPostalAddress

@objc public class SSKProtoDataMessageContactPostalAddress: NSObject {

	// MARK: - SSKProtoDataMessageContactPostalAddressType

	@objc public enum SSKProtoDataMessageContactPostalAddressType: Int32 {
		case home = 1
		case work = 2
		case custom = 3
	}

	private class func SSKProtoDataMessageContactPostalAddressTypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SSKProtoDataMessageContactPostalAddressType {
		switch value {
		case .home: return .home
		case .work: return .work
		case .custom: return .custom
		}
	}

	private class func SSKProtoDataMessageContactPostalAddressTypeUnwrap(_ value: SSKProtoDataMessageContactPostalAddressType) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
		switch value {
		case .home: return .home
		case .work: return .work
		case .custom: return .custom
		}
	}

	@objc public let type: SSKProtoDataMessageContactPostalAddressType
	@objc public let label: String?
	@objc public let street: String?
	@objc public let pobox: String?
	@objc public let neighborhood: String?
	@objc public let city: String?
	@objc public let region: String?
	@objc public let postcode: String?
	@objc public let country: String?

	@objc public init(type: SSKProtoDataMessageContactPostalAddressType,
	                  label: String?,
	                  street: String?,
	                  pobox: String?,
	                  neighborhood: String?,
	                  city: String?,
	                  region: String?,
	                  postcode: String?,
	                  country: String?) {
		self.type = type
		self.label = label
		self.street = street
		self.pobox = pobox
		self.neighborhood = neighborhood
		self.city = city
		self.region = region
		self.postcode = postcode
		self.country = country
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactPostalAddress {
		let proto = try SignalServiceProtos_DataMessage.Contact.PostalAddress(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.PostalAddress) throws -> SSKProtoDataMessageContactPostalAddress {
		var type: SSKProtoDataMessageContactPostalAddressType = .home
		if proto.hasType {
			type = SSKProtoDataMessageContactPostalAddressTypeWrap(proto.type)
		}

		var label: String? = nil
		if proto.hasLabel {
			label = proto.label
		}

		var street: String? = nil
		if proto.hasStreet {
			street = proto.street
		}

		var pobox: String? = nil
		if proto.hasPobox {
			pobox = proto.pobox
		}

		var neighborhood: String? = nil
		if proto.hasNeighborhood {
			neighborhood = proto.neighborhood
		}

		var city: String? = nil
		if proto.hasCity {
			city = proto.city
		}

		var region: String? = nil
		if proto.hasRegion {
			region = proto.region
		}

		var postcode: String? = nil
		if proto.hasPostcode {
			postcode = proto.postcode
		}

		var country: String? = nil
		if proto.hasCountry {
			country = proto.country
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContactPostalAddress -

		// MARK: - End Validation Logic for SSKProtoDataMessageContactPostalAddress -

		let result = SSKProtoDataMessageContactPostalAddress(type: type,
		                                                     label: label,
		                                                     street: street,
		                                                     pobox: pobox,
		                                                     neighborhood: neighborhood,
		                                                     city: city,
		                                                     region: region,
		                                                     postcode: postcode,
		                                                     country: country)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.PostalAddress {
		let proto = SignalServiceProtos_DataMessage.Contact.PostalAddress.with { (builder) in
			builder.type = SSKProtoDataMessageContactPostalAddress.SSKProtoDataMessageContactPostalAddressTypeUnwrap(self.type)

			if let label = self.label {
				builder.label = label
			}

			if let street = self.street {
				builder.street = street
			}

			if let pobox = self.pobox {
				builder.pobox = pobox
			}

			if let neighborhood = self.neighborhood {
				builder.neighborhood = neighborhood
			}

			if let city = self.city {
				builder.city = city
			}

			if let region = self.region {
				builder.region = region
			}

			if let postcode = self.postcode {
				builder.postcode = postcode
			}

			if let country = self.country {
				builder.country = country
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContactAvatar

@objc public class SSKProtoDataMessageContactAvatar: NSObject {

	@objc public let avatar: SSKProtoAttachmentPointer?
	@objc public let isProfile: Bool

	@objc public init(avatar: SSKProtoAttachmentPointer?,
	                  isProfile: Bool) {
		self.avatar = avatar
		self.isProfile = isProfile
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContactAvatar {
		let proto = try SignalServiceProtos_DataMessage.Contact.Avatar(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact.Avatar) throws -> SSKProtoDataMessageContactAvatar {
		var avatar: SSKProtoAttachmentPointer? = nil
		if proto.hasAvatar {
			avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
		}

		var isProfile: Bool = false
		if proto.hasIsProfile {
			isProfile = proto.isProfile
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContactAvatar -

		// MARK: - End Validation Logic for SSKProtoDataMessageContactAvatar -

		let result = SSKProtoDataMessageContactAvatar(avatar: avatar,
		                                              isProfile: isProfile)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Avatar {
		let proto = SignalServiceProtos_DataMessage.Contact.Avatar.with { (builder) in
			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			builder.isProfile = self.isProfile
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessageContact

@objc public class SSKProtoDataMessageContact: NSObject {

	@objc public let name: SSKProtoDataMessageContactName?
	@objc public let number: [SSKProtoDataMessageContactPhone]
	@objc public let email: [SSKProtoDataMessageContactEmail]
	@objc public let address: [SSKProtoDataMessageContactPostalAddress]
	@objc public let avatar: SSKProtoDataMessageContactAvatar?
	@objc public let organization: String?

	@objc public init(name: SSKProtoDataMessageContactName?,
	                  number: [SSKProtoDataMessageContactPhone],
	                  email: [SSKProtoDataMessageContactEmail],
	                  address: [SSKProtoDataMessageContactPostalAddress],
	                  avatar: SSKProtoDataMessageContactAvatar?,
	                  organization: String?) {
		self.name = name
		self.number = number
		self.email = email
		self.address = address
		self.avatar = avatar
		self.organization = organization
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessageContact {
		let proto = try SignalServiceProtos_DataMessage.Contact(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage.Contact) throws -> SSKProtoDataMessageContact {
		var name: SSKProtoDataMessageContactName? = nil
		if proto.hasName {
			name = try SSKProtoDataMessageContactName.parseProto(proto.name)
		}

		var number: [SSKProtoDataMessageContactPhone] = []
		for item in proto.number {
			let wrapped = try SSKProtoDataMessageContactPhone.parseProto(item)
			number.append(wrapped)
		}

		var email: [SSKProtoDataMessageContactEmail] = []
		for item in proto.email {
			let wrapped = try SSKProtoDataMessageContactEmail.parseProto(item)
			email.append(wrapped)
		}

		var address: [SSKProtoDataMessageContactPostalAddress] = []
		for item in proto.address {
			let wrapped = try SSKProtoDataMessageContactPostalAddress.parseProto(item)
			address.append(wrapped)
		}

		var avatar: SSKProtoDataMessageContactAvatar? = nil
		if proto.hasAvatar {
			avatar = try SSKProtoDataMessageContactAvatar.parseProto(proto.avatar)
		}

		var organization: String? = nil
		if proto.hasOrganization {
			organization = proto.organization
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessageContact -

		// MARK: - End Validation Logic for SSKProtoDataMessageContact -

		let result = SSKProtoDataMessageContact(name: name,
		                                        number: number,
		                                        email: email,
		                                        address: address,
		                                        avatar: avatar,
		                                        organization: organization)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact {
		let proto = SignalServiceProtos_DataMessage.Contact.with { (builder) in
			if let name = self.name {
				builder.name = name.asProtobuf
			}

			var numberUnwrapped = [SignalServiceProtos_DataMessage.Contact.Phone]()
			for item in number {
				numberUnwrapped.append(item.asProtobuf)
			}
			builder.number = numberUnwrapped

			var emailUnwrapped = [SignalServiceProtos_DataMessage.Contact.Email]()
			for item in email {
				emailUnwrapped.append(item.asProtobuf)
			}
			builder.email = emailUnwrapped

			var addressUnwrapped = [SignalServiceProtos_DataMessage.Contact.PostalAddress]()
			for item in address {
				addressUnwrapped.append(item.asProtobuf)
			}
			builder.address = addressUnwrapped

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			if let organization = self.organization {
				builder.organization = organization
			}
		}

		return proto
	}
}

// MARK: - SSKProtoDataMessage

@objc public class SSKProtoDataMessage: NSObject {

	// MARK: - SSKProtoDataMessageFlags

	@objc public enum SSKProtoDataMessageFlags: Int32 {
		case endSession = 1
		case expirationTimerUpdate = 2
		case profileKeyUpdate = 4
	}

	private class func SSKProtoDataMessageFlagsWrap(_ value: SignalServiceProtos_DataMessage.Flags) -> SSKProtoDataMessageFlags {
		switch value {
		case .endSession: return .endSession
		case .expirationTimerUpdate: return .expirationTimerUpdate
		case .profileKeyUpdate: return .profileKeyUpdate
		}
	}

	private class func SSKProtoDataMessageFlagsUnwrap(_ value: SSKProtoDataMessageFlags) -> SignalServiceProtos_DataMessage.Flags {
		switch value {
		case .endSession: return .endSession
		case .expirationTimerUpdate: return .expirationTimerUpdate
		case .profileKeyUpdate: return .profileKeyUpdate
		}
	}

	@objc public let body: String?
	@objc public let attachments: [SSKProtoAttachmentPointer]
	@objc public let group: SSKProtoGroupContext?
	@objc public let flags: UInt32
	@objc public let expireTimer: UInt32
	@objc public let profileKey: Data?
	@objc public let timestamp: UInt64
	@objc public let quote: SSKProtoDataMessageQuote?
	@objc public let contact: [SSKProtoDataMessageContact]

	@objc public init(body: String?,
	                  attachments: [SSKProtoAttachmentPointer],
	                  group: SSKProtoGroupContext?,
	                  flags: UInt32,
	                  expireTimer: UInt32,
	                  profileKey: Data?,
	                  timestamp: UInt64,
	                  quote: SSKProtoDataMessageQuote?,
	                  contact: [SSKProtoDataMessageContact]) {
		self.body = body
		self.attachments = attachments
		self.group = group
		self.flags = flags
		self.expireTimer = expireTimer
		self.profileKey = profileKey
		self.timestamp = timestamp
		self.quote = quote
		self.contact = contact
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoDataMessage {
		let proto = try SignalServiceProtos_DataMessage(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_DataMessage) throws -> SSKProtoDataMessage {
		var body: String? = nil
		if proto.hasBody {
			body = proto.body
		}

		var attachments: [SSKProtoAttachmentPointer] = []
		for item in proto.attachments {
			let wrapped = try SSKProtoAttachmentPointer.parseProto(item)
			attachments.append(wrapped)
		}

		var group: SSKProtoGroupContext? = nil
		if proto.hasGroup {
			group = try SSKProtoGroupContext.parseProto(proto.group)
		}

		var flags: UInt32 = 0
		if proto.hasFlags {
			flags = proto.flags
		}

		var expireTimer: UInt32 = 0
		if proto.hasExpireTimer {
			expireTimer = proto.expireTimer
		}

		var profileKey: Data? = nil
		if proto.hasProfileKey {
			profileKey = proto.profileKey
		}

		var timestamp: UInt64 = 0
		if proto.hasTimestamp {
			timestamp = proto.timestamp
		}

		var quote: SSKProtoDataMessageQuote? = nil
		if proto.hasQuote {
			quote = try SSKProtoDataMessageQuote.parseProto(proto.quote)
		}

		var contact: [SSKProtoDataMessageContact] = []
		for item in proto.contact {
			let wrapped = try SSKProtoDataMessageContact.parseProto(item)
			contact.append(wrapped)
		}

		// MARK: - Begin Validation Logic for SSKProtoDataMessage -

		// MARK: - End Validation Logic for SSKProtoDataMessage -

		let result = SSKProtoDataMessage(body: body,
		                                 attachments: attachments,
		                                 group: group,
		                                 flags: flags,
		                                 expireTimer: expireTimer,
		                                 profileKey: profileKey,
		                                 timestamp: timestamp,
		                                 quote: quote,
		                                 contact: contact)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage {
		let proto = SignalServiceProtos_DataMessage.with { (builder) in
			if let body = self.body {
				builder.body = body
			}

			var attachmentsUnwrapped = [SignalServiceProtos_AttachmentPointer]()
			for item in attachments {
				attachmentsUnwrapped.append(item.asProtobuf)
			}
			builder.attachments = attachmentsUnwrapped

			if let group = self.group {
				builder.group = group.asProtobuf
			}

			builder.flags = self.flags

			builder.expireTimer = self.expireTimer

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}

			builder.timestamp = self.timestamp

			if let quote = self.quote {
				builder.quote = quote.asProtobuf
			}

			var contactUnwrapped = [SignalServiceProtos_DataMessage.Contact]()
			for item in contact {
				contactUnwrapped.append(item.asProtobuf)
			}
			builder.contact = contactUnwrapped
		}

		return proto
	}
}

// MARK: - SSKProtoNullMessage

@objc public class SSKProtoNullMessage: NSObject {

	@objc public let padding: Data?

	@objc public init(padding: Data?) {
		self.padding = padding
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoNullMessage {
		let proto = try SignalServiceProtos_NullMessage(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_NullMessage) throws -> SSKProtoNullMessage {
		var padding: Data? = nil
		if proto.hasPadding {
			padding = proto.padding
		}

		// MARK: - Begin Validation Logic for SSKProtoNullMessage -

		// MARK: - End Validation Logic for SSKProtoNullMessage -

		let result = SSKProtoNullMessage(padding: padding)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_NullMessage {
		let proto = SignalServiceProtos_NullMessage.with { (builder) in
			if let padding = self.padding {
				builder.padding = padding
			}
		}

		return proto
	}
}

// MARK: - SSKProtoReceiptMessage

@objc public class SSKProtoReceiptMessage: NSObject {

	// MARK: - SSKProtoReceiptMessageType

	@objc public enum SSKProtoReceiptMessageType: Int32 {
		case delivery = 0
		case read = 1
	}

	private class func SSKProtoReceiptMessageTypeWrap(_ value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SSKProtoReceiptMessageType {
		switch value {
		case .delivery: return .delivery
		case .read: return .read
		}
	}

	private class func SSKProtoReceiptMessageTypeUnwrap(_ value: SSKProtoReceiptMessageType) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
		switch value {
		case .delivery: return .delivery
		case .read: return .read
		}
	}

	@objc public let type: SSKProtoReceiptMessageType
	@objc public let timestamp: [UInt64]

	@objc public init(type: SSKProtoReceiptMessageType,
	                  timestamp: [UInt64]) {
		self.type = type
		self.timestamp = timestamp
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoReceiptMessage {
		let proto = try SignalServiceProtos_ReceiptMessage(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_ReceiptMessage) throws -> SSKProtoReceiptMessage {
		var type: SSKProtoReceiptMessageType = .delivery
		if proto.hasType {
			type = SSKProtoReceiptMessageTypeWrap(proto.type)
		}

		var timestamp: [UInt64] = []
		for item in proto.timestamp {
			let wrapped = item
			timestamp.append(wrapped)
		}

		// MARK: - Begin Validation Logic for SSKProtoReceiptMessage -

        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

		// MARK: - End Validation Logic for SSKProtoReceiptMessage -

		let result = SSKProtoReceiptMessage(type: type,
		                                    timestamp: timestamp)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_ReceiptMessage {
		let proto = SignalServiceProtos_ReceiptMessage.with { (builder) in
			builder.type = SSKProtoReceiptMessage.SSKProtoReceiptMessageTypeUnwrap(self.type)

			var timestampUnwrapped = [UInt64]()
			for item in timestamp {
				timestampUnwrapped.append(item)
			}
			builder.timestamp = timestampUnwrapped
		}

		return proto
	}
}

// MARK: - SSKProtoVerified

@objc public class SSKProtoVerified: NSObject {

	// MARK: - SSKProtoVerifiedState

	@objc public enum SSKProtoVerifiedState: Int32 {
		case `default` = 0
		case verified = 1
		case unverified = 2
	}

	private class func SSKProtoVerifiedStateWrap(_ value: SignalServiceProtos_Verified.State) -> SSKProtoVerifiedState {
		switch value {
		case .default: return .default
		case .verified: return .verified
		case .unverified: return .unverified
		}
	}

	private class func SSKProtoVerifiedStateUnwrap(_ value: SSKProtoVerifiedState) -> SignalServiceProtos_Verified.State {
		switch value {
		case .default: return .default
		case .verified: return .verified
		case .unverified: return .unverified
		}
	}

	@objc public let destination: String?
	@objc public let identityKey: Data?
	@objc public let state: SSKProtoVerifiedState
	@objc public let nullMessage: Data?

	@objc public init(destination: String?,
	                  identityKey: Data?,
	                  state: SSKProtoVerifiedState,
	                  nullMessage: Data?) {
		self.destination = destination
		self.identityKey = identityKey
		self.state = state
		self.nullMessage = nullMessage
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoVerified {
		let proto = try SignalServiceProtos_Verified(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_Verified) throws -> SSKProtoVerified {
		var destination: String? = nil
		if proto.hasDestination {
			destination = proto.destination
		}

		var identityKey: Data? = nil
		if proto.hasIdentityKey {
			identityKey = proto.identityKey
		}

		var state: SSKProtoVerifiedState = .default
		if proto.hasState {
			state = SSKProtoVerifiedStateWrap(proto.state)
		}

		var nullMessage: Data? = nil
		if proto.hasNullMessage {
			nullMessage = proto.nullMessage
		}

		// MARK: - Begin Validation Logic for SSKProtoVerified -

		// MARK: - End Validation Logic for SSKProtoVerified -

		let result = SSKProtoVerified(destination: destination,
		                              identityKey: identityKey,
		                              state: state,
		                              nullMessage: nullMessage)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_Verified {
		let proto = SignalServiceProtos_Verified.with { (builder) in
			if let destination = self.destination {
				builder.destination = destination
			}

			if let identityKey = self.identityKey {
				builder.identityKey = identityKey
			}

			builder.state = SSKProtoVerified.SSKProtoVerifiedStateUnwrap(self.state)

			if let nullMessage = self.nullMessage {
				builder.nullMessage = nullMessage
			}
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageSent

@objc public class SSKProtoSyncMessageSent: NSObject {

	@objc public let destination: String?
	@objc public let timestamp: UInt64
	@objc public let message: SSKProtoDataMessage?
	@objc public let expirationStartTimestamp: UInt64

	@objc public init(destination: String?,
	                  timestamp: UInt64,
	                  message: SSKProtoDataMessage?,
	                  expirationStartTimestamp: UInt64) {
		self.destination = destination
		self.timestamp = timestamp
		self.message = message
		self.expirationStartTimestamp = expirationStartTimestamp
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageSent {
		let proto = try SignalServiceProtos_SyncMessage.Sent(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Sent) throws -> SSKProtoSyncMessageSent {
		var destination: String? = nil
		if proto.hasDestination {
			destination = proto.destination
		}

		var timestamp: UInt64 = 0
		if proto.hasTimestamp {
			timestamp = proto.timestamp
		}

		var message: SSKProtoDataMessage? = nil
		if proto.hasMessage {
			message = try SSKProtoDataMessage.parseProto(proto.message)
		}

		var expirationStartTimestamp: UInt64 = 0
		if proto.hasExpirationStartTimestamp {
			expirationStartTimestamp = proto.expirationStartTimestamp
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageSent -

		// MARK: - End Validation Logic for SSKProtoSyncMessageSent -

		let result = SSKProtoSyncMessageSent(destination: destination,
		                                     timestamp: timestamp,
		                                     message: message,
		                                     expirationStartTimestamp: expirationStartTimestamp)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Sent {
		let proto = SignalServiceProtos_SyncMessage.Sent.with { (builder) in
			if let destination = self.destination {
				builder.destination = destination
			}

			builder.timestamp = self.timestamp

			if let message = self.message {
				builder.message = message.asProtobuf
			}

			builder.expirationStartTimestamp = self.expirationStartTimestamp
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageContacts

@objc public class SSKProtoSyncMessageContacts: NSObject {

	@objc public let blob: SSKProtoAttachmentPointer?
	@objc public let isComplete: Bool

	@objc public init(blob: SSKProtoAttachmentPointer?,
	                  isComplete: Bool) {
		self.blob = blob
		self.isComplete = isComplete
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageContacts {
		let proto = try SignalServiceProtos_SyncMessage.Contacts(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Contacts) throws -> SSKProtoSyncMessageContacts {
		var blob: SSKProtoAttachmentPointer? = nil
		if proto.hasBlob {
			blob = try SSKProtoAttachmentPointer.parseProto(proto.blob)
		}

		var isComplete: Bool = false
		if proto.hasIsComplete {
			isComplete = proto.isComplete
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageContacts -

        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: blob")
        }

		// MARK: - End Validation Logic for SSKProtoSyncMessageContacts -

		let result = SSKProtoSyncMessageContacts(blob: blob,
		                                         isComplete: isComplete)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Contacts {
		let proto = SignalServiceProtos_SyncMessage.Contacts.with { (builder) in
			if let blob = self.blob {
				builder.blob = blob.asProtobuf
			}

			builder.isComplete = self.isComplete
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageGroups

@objc public class SSKProtoSyncMessageGroups: NSObject {

	@objc public let blob: SSKProtoAttachmentPointer?

	@objc public init(blob: SSKProtoAttachmentPointer?) {
		self.blob = blob
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageGroups {
		let proto = try SignalServiceProtos_SyncMessage.Groups(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Groups) throws -> SSKProtoSyncMessageGroups {
		var blob: SSKProtoAttachmentPointer? = nil
		if proto.hasBlob {
			blob = try SSKProtoAttachmentPointer.parseProto(proto.blob)
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageGroups -

        guard proto.hasBlob else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: blob")
        }

		// MARK: - End Validation Logic for SSKProtoSyncMessageGroups -

		let result = SSKProtoSyncMessageGroups(blob: blob)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Groups {
		let proto = SignalServiceProtos_SyncMessage.Groups.with { (builder) in
			if let blob = self.blob {
				builder.blob = blob.asProtobuf
			}
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageBlocked

@objc public class SSKProtoSyncMessageBlocked: NSObject {

	@objc public let numbers: [String]

	@objc public init(numbers: [String]) {
		self.numbers = numbers
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageBlocked {
		let proto = try SignalServiceProtos_SyncMessage.Blocked(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Blocked) throws -> SSKProtoSyncMessageBlocked {
		var numbers: [String] = []
		for item in proto.numbers {
			let wrapped = item
			numbers.append(wrapped)
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageBlocked -

		// MARK: - End Validation Logic for SSKProtoSyncMessageBlocked -

		let result = SSKProtoSyncMessageBlocked(numbers: numbers)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Blocked {
		let proto = SignalServiceProtos_SyncMessage.Blocked.with { (builder) in
			var numbersUnwrapped = [String]()
			for item in numbers {
				numbersUnwrapped.append(item)
			}
			builder.numbers = numbersUnwrapped
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageRequest

@objc public class SSKProtoSyncMessageRequest: NSObject {

	// MARK: - SSKProtoSyncMessageRequestType

	@objc public enum SSKProtoSyncMessageRequestType: Int32 {
		case unknown = 0
		case contacts = 1
		case groups = 2
		case blocked = 3
		case configuration = 4
	}

	private class func SSKProtoSyncMessageRequestTypeWrap(_ value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SSKProtoSyncMessageRequestType {
		switch value {
		case .unknown: return .unknown
		case .contacts: return .contacts
		case .groups: return .groups
		case .blocked: return .blocked
		case .configuration: return .configuration
		}
	}

	private class func SSKProtoSyncMessageRequestTypeUnwrap(_ value: SSKProtoSyncMessageRequestType) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
		switch value {
		case .unknown: return .unknown
		case .contacts: return .contacts
		case .groups: return .groups
		case .blocked: return .blocked
		case .configuration: return .configuration
		}
	}

	@objc public let type: SSKProtoSyncMessageRequestType

	@objc public init(type: SSKProtoSyncMessageRequestType) {
		self.type = type
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageRequest {
		let proto = try SignalServiceProtos_SyncMessage.Request(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Request) throws -> SSKProtoSyncMessageRequest {
		var type: SSKProtoSyncMessageRequestType = .unknown
		if proto.hasType {
			type = SSKProtoSyncMessageRequestTypeWrap(proto.type)
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageRequest -

        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

		// MARK: - End Validation Logic for SSKProtoSyncMessageRequest -

		let result = SSKProtoSyncMessageRequest(type: type)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Request {
		let proto = SignalServiceProtos_SyncMessage.Request.with { (builder) in
			builder.type = SSKProtoSyncMessageRequest.SSKProtoSyncMessageRequestTypeUnwrap(self.type)
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageRead

@objc public class SSKProtoSyncMessageRead: NSObject {

	@objc public let sender: String?
	@objc public let timestamp: UInt64

	@objc public init(sender: String?,
	                  timestamp: UInt64) {
		self.sender = sender
		self.timestamp = timestamp
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageRead {
		let proto = try SignalServiceProtos_SyncMessage.Read(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Read) throws -> SSKProtoSyncMessageRead {
		var sender: String? = nil
		if proto.hasSender {
			sender = proto.sender
		}

		var timestamp: UInt64 = 0
		if proto.hasTimestamp {
			timestamp = proto.timestamp
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageRead -

        guard proto.hasSender else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: sender")
        }
        guard proto.hasTimestamp else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: timestamp")
        }

		// MARK: - End Validation Logic for SSKProtoSyncMessageRead -

		let result = SSKProtoSyncMessageRead(sender: sender,
		                                     timestamp: timestamp)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Read {
		let proto = SignalServiceProtos_SyncMessage.Read.with { (builder) in
			if let sender = self.sender {
				builder.sender = sender
			}

			builder.timestamp = self.timestamp
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessageConfiguration

@objc public class SSKProtoSyncMessageConfiguration: NSObject {

	@objc public let readReceipts: Bool

	@objc public init(readReceipts: Bool) {
		self.readReceipts = readReceipts
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessageConfiguration {
		let proto = try SignalServiceProtos_SyncMessage.Configuration(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage.Configuration) throws -> SSKProtoSyncMessageConfiguration {
		var readReceipts: Bool = false
		if proto.hasReadReceipts {
			readReceipts = proto.readReceipts
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessageConfiguration -

		// MARK: - End Validation Logic for SSKProtoSyncMessageConfiguration -

		let result = SSKProtoSyncMessageConfiguration(readReceipts: readReceipts)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Configuration {
		let proto = SignalServiceProtos_SyncMessage.Configuration.with { (builder) in
			builder.readReceipts = self.readReceipts
		}

		return proto
	}
}

// MARK: - SSKProtoSyncMessage

@objc public class SSKProtoSyncMessage: NSObject {

	@objc public let sent: SSKProtoSyncMessageSent?
	@objc public let contacts: SSKProtoSyncMessageContacts?
	@objc public let groups: SSKProtoSyncMessageGroups?
	@objc public let request: SSKProtoSyncMessageRequest?
	@objc public let read: [SSKProtoSyncMessageRead]
	@objc public let blocked: SSKProtoSyncMessageBlocked?
	@objc public let verified: SSKProtoVerified?
	@objc public let configuration: SSKProtoSyncMessageConfiguration?
	@objc public let padding: Data?

	@objc public init(sent: SSKProtoSyncMessageSent?,
	                  contacts: SSKProtoSyncMessageContacts?,
	                  groups: SSKProtoSyncMessageGroups?,
	                  request: SSKProtoSyncMessageRequest?,
	                  read: [SSKProtoSyncMessageRead],
	                  blocked: SSKProtoSyncMessageBlocked?,
	                  verified: SSKProtoVerified?,
	                  configuration: SSKProtoSyncMessageConfiguration?,
	                  padding: Data?) {
		self.sent = sent
		self.contacts = contacts
		self.groups = groups
		self.request = request
		self.read = read
		self.blocked = blocked
		self.verified = verified
		self.configuration = configuration
		self.padding = padding
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoSyncMessage {
		let proto = try SignalServiceProtos_SyncMessage(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_SyncMessage) throws -> SSKProtoSyncMessage {
		var sent: SSKProtoSyncMessageSent? = nil
		if proto.hasSent {
			sent = try SSKProtoSyncMessageSent.parseProto(proto.sent)
		}

		var contacts: SSKProtoSyncMessageContacts? = nil
		if proto.hasContacts {
			contacts = try SSKProtoSyncMessageContacts.parseProto(proto.contacts)
		}

		var groups: SSKProtoSyncMessageGroups? = nil
		if proto.hasGroups {
			groups = try SSKProtoSyncMessageGroups.parseProto(proto.groups)
		}

		var request: SSKProtoSyncMessageRequest? = nil
		if proto.hasRequest {
			request = try SSKProtoSyncMessageRequest.parseProto(proto.request)
		}

		var read: [SSKProtoSyncMessageRead] = []
		for item in proto.read {
			let wrapped = try SSKProtoSyncMessageRead.parseProto(item)
			read.append(wrapped)
		}

		var blocked: SSKProtoSyncMessageBlocked? = nil
		if proto.hasBlocked {
			blocked = try SSKProtoSyncMessageBlocked.parseProto(proto.blocked)
		}

		var verified: SSKProtoVerified? = nil
		if proto.hasVerified {
			verified = try SSKProtoVerified.parseProto(proto.verified)
		}

		var configuration: SSKProtoSyncMessageConfiguration? = nil
		if proto.hasConfiguration {
			configuration = try SSKProtoSyncMessageConfiguration.parseProto(proto.configuration)
		}

		var padding: Data? = nil
		if proto.hasPadding {
			padding = proto.padding
		}

		// MARK: - Begin Validation Logic for SSKProtoSyncMessage -

		// MARK: - End Validation Logic for SSKProtoSyncMessage -

		let result = SSKProtoSyncMessage(sent: sent,
		                                 contacts: contacts,
		                                 groups: groups,
		                                 request: request,
		                                 read: read,
		                                 blocked: blocked,
		                                 verified: verified,
		                                 configuration: configuration,
		                                 padding: padding)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage {
		let proto = SignalServiceProtos_SyncMessage.with { (builder) in
			if let sent = self.sent {
				builder.sent = sent.asProtobuf
			}

			if let contacts = self.contacts {
				builder.contacts = contacts.asProtobuf
			}

			if let groups = self.groups {
				builder.groups = groups.asProtobuf
			}

			if let request = self.request {
				builder.request = request.asProtobuf
			}

			var readUnwrapped = [SignalServiceProtos_SyncMessage.Read]()
			for item in read {
				readUnwrapped.append(item.asProtobuf)
			}
			builder.read = readUnwrapped

			if let blocked = self.blocked {
				builder.blocked = blocked.asProtobuf
			}

			if let verified = self.verified {
				builder.verified = verified.asProtobuf
			}

			if let configuration = self.configuration {
				builder.configuration = configuration.asProtobuf
			}

			if let padding = self.padding {
				builder.padding = padding
			}
		}

		return proto
	}
}

// MARK: - SSKProtoAttachmentPointer

@objc public class SSKProtoAttachmentPointer: NSObject {

	// MARK: - SSKProtoAttachmentPointerFlags

	@objc public enum SSKProtoAttachmentPointerFlags: Int32 {
		case voiceMessage = 1
	}

	private class func SSKProtoAttachmentPointerFlagsWrap(_ value: SignalServiceProtos_AttachmentPointer.Flags) -> SSKProtoAttachmentPointerFlags {
		switch value {
		case .voiceMessage: return .voiceMessage
		}
	}

	private class func SSKProtoAttachmentPointerFlagsUnwrap(_ value: SSKProtoAttachmentPointerFlags) -> SignalServiceProtos_AttachmentPointer.Flags {
		switch value {
		case .voiceMessage: return .voiceMessage
		}
	}

	@objc public let id: UInt64
	@objc public let contentType: String?
	@objc public let key: Data?
	@objc public let size: UInt32
	@objc public let thumbnail: Data?
	@objc public let digest: Data?
	@objc public let fileName: String?
	@objc public let flags: UInt32
	@objc public let width: UInt32
	@objc public let height: UInt32

	@objc public init(id: UInt64,
	                  contentType: String?,
	                  key: Data?,
	                  size: UInt32,
	                  thumbnail: Data?,
	                  digest: Data?,
	                  fileName: String?,
	                  flags: UInt32,
	                  width: UInt32,
	                  height: UInt32) {
		self.id = id
		self.contentType = contentType
		self.key = key
		self.size = size
		self.thumbnail = thumbnail
		self.digest = digest
		self.fileName = fileName
		self.flags = flags
		self.width = width
		self.height = height
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoAttachmentPointer {
		let proto = try SignalServiceProtos_AttachmentPointer(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_AttachmentPointer) throws -> SSKProtoAttachmentPointer {
		var id: UInt64 = 0
		if proto.hasID {
			id = proto.id
		}

		var contentType: String? = nil
		if proto.hasContentType {
			contentType = proto.contentType
		}

		var key: Data? = nil
		if proto.hasKey {
			key = proto.key
		}

		var size: UInt32 = 0
		if proto.hasSize {
			size = proto.size
		}

		var thumbnail: Data? = nil
		if proto.hasThumbnail {
			thumbnail = proto.thumbnail
		}

		var digest: Data? = nil
		if proto.hasDigest {
			digest = proto.digest
		}

		var fileName: String? = nil
		if proto.hasFileName {
			fileName = proto.fileName
		}

		var flags: UInt32 = 0
		if proto.hasFlags {
			flags = proto.flags
		}

		var width: UInt32 = 0
		if proto.hasWidth {
			width = proto.width
		}

		var height: UInt32 = 0
		if proto.hasHeight {
			height = proto.height
		}

		// MARK: - Begin Validation Logic for SSKProtoAttachmentPointer -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }

		// MARK: - End Validation Logic for SSKProtoAttachmentPointer -

		let result = SSKProtoAttachmentPointer(id: id,
		                                       contentType: contentType,
		                                       key: key,
		                                       size: size,
		                                       thumbnail: thumbnail,
		                                       digest: digest,
		                                       fileName: fileName,
		                                       flags: flags,
		                                       width: width,
		                                       height: height)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_AttachmentPointer {
		let proto = SignalServiceProtos_AttachmentPointer.with { (builder) in
			builder.id = self.id

			if let contentType = self.contentType {
				builder.contentType = contentType
			}

			if let key = self.key {
				builder.key = key
			}

			builder.size = self.size

			if let thumbnail = self.thumbnail {
				builder.thumbnail = thumbnail
			}

			if let digest = self.digest {
				builder.digest = digest
			}

			if let fileName = self.fileName {
				builder.fileName = fileName
			}

			builder.flags = self.flags

			builder.width = self.width

			builder.height = self.height
		}

		return proto
	}
}

// MARK: - SSKProtoGroupContext

@objc public class SSKProtoGroupContext: NSObject {

	// MARK: - SSKProtoGroupContextType

	@objc public enum SSKProtoGroupContextType: Int32 {
		case unknown = 0
		case update = 1
		case deliver = 2
		case quit = 3
		case requestInfo = 4
	}

	private class func SSKProtoGroupContextTypeWrap(_ value: SignalServiceProtos_GroupContext.TypeEnum) -> SSKProtoGroupContextType {
		switch value {
		case .unknown: return .unknown
		case .update: return .update
		case .deliver: return .deliver
		case .quit: return .quit
		case .requestInfo: return .requestInfo
		}
	}

	private class func SSKProtoGroupContextTypeUnwrap(_ value: SSKProtoGroupContextType) -> SignalServiceProtos_GroupContext.TypeEnum {
		switch value {
		case .unknown: return .unknown
		case .update: return .update
		case .deliver: return .deliver
		case .quit: return .quit
		case .requestInfo: return .requestInfo
		}
	}

	@objc public let id: Data?
	@objc public let type: SSKProtoGroupContextType
	@objc public let name: String?
	@objc public let members: [String]
	@objc public let avatar: SSKProtoAttachmentPointer?

	@objc public init(id: Data?,
	                  type: SSKProtoGroupContextType,
	                  name: String?,
	                  members: [String],
	                  avatar: SSKProtoAttachmentPointer?) {
		self.id = id
		self.type = type
		self.name = name
		self.members = members
		self.avatar = avatar
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupContext {
		let proto = try SignalServiceProtos_GroupContext(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupContext) throws -> SSKProtoGroupContext {
		var id: Data? = nil
		if proto.hasID {
			id = proto.id
		}

		var type: SSKProtoGroupContextType = .unknown
		if proto.hasType {
			type = SSKProtoGroupContextTypeWrap(proto.type)
		}

		var name: String? = nil
		if proto.hasName {
			name = proto.name
		}

		var members: [String] = []
		for item in proto.members {
			let wrapped = item
			members.append(wrapped)
		}

		var avatar: SSKProtoAttachmentPointer? = nil
		if proto.hasAvatar {
			avatar = try SSKProtoAttachmentPointer.parseProto(proto.avatar)
		}

		// MARK: - Begin Validation Logic for SSKProtoGroupContext -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }
        guard proto.hasType else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: type")
        }

		// MARK: - End Validation Logic for SSKProtoGroupContext -

		let result = SSKProtoGroupContext(id: id,
		                                  type: type,
		                                  name: name,
		                                  members: members,
		                                  avatar: avatar)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_GroupContext {
		let proto = SignalServiceProtos_GroupContext.with { (builder) in
			if let id = self.id {
				builder.id = id
			}

			builder.type = SSKProtoGroupContext.SSKProtoGroupContextTypeUnwrap(self.type)

			if let name = self.name {
				builder.name = name
			}

			var membersUnwrapped = [String]()
			for item in members {
				membersUnwrapped.append(item)
			}
			builder.members = membersUnwrapped

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}
		}

		return proto
	}
}

// MARK: - SSKProtoContactDetailsAvatar

@objc public class SSKProtoContactDetailsAvatar: NSObject {

	@objc public let contentType: String?
	@objc public let length: UInt32

	@objc public init(contentType: String?,
	                  length: UInt32) {
		self.contentType = contentType
		self.length = length
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContactDetailsAvatar {
		let proto = try SignalServiceProtos_ContactDetails.Avatar(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_ContactDetails.Avatar) throws -> SSKProtoContactDetailsAvatar {
		var contentType: String? = nil
		if proto.hasContentType {
			contentType = proto.contentType
		}

		var length: UInt32 = 0
		if proto.hasLength {
			length = proto.length
		}

		// MARK: - Begin Validation Logic for SSKProtoContactDetailsAvatar -

		// MARK: - End Validation Logic for SSKProtoContactDetailsAvatar -

		let result = SSKProtoContactDetailsAvatar(contentType: contentType,
		                                          length: length)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_ContactDetails.Avatar {
		let proto = SignalServiceProtos_ContactDetails.Avatar.with { (builder) in
			if let contentType = self.contentType {
				builder.contentType = contentType
			}

			builder.length = self.length
		}

		return proto
	}
}

// MARK: - SSKProtoContactDetails

@objc public class SSKProtoContactDetails: NSObject {

	@objc public let number: String?
	@objc public let name: String?
	@objc public let avatar: SSKProtoContactDetailsAvatar?
	@objc public let color: String?
	@objc public let verified: SSKProtoVerified?
	@objc public let profileKey: Data?
	@objc public let blocked: Bool
	@objc public let expireTimer: UInt32

	@objc public init(number: String?,
	                  name: String?,
	                  avatar: SSKProtoContactDetailsAvatar?,
	                  color: String?,
	                  verified: SSKProtoVerified?,
	                  profileKey: Data?,
	                  blocked: Bool,
	                  expireTimer: UInt32) {
		self.number = number
		self.name = name
		self.avatar = avatar
		self.color = color
		self.verified = verified
		self.profileKey = profileKey
		self.blocked = blocked
		self.expireTimer = expireTimer
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoContactDetails {
		let proto = try SignalServiceProtos_ContactDetails(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_ContactDetails) throws -> SSKProtoContactDetails {
		var number: String? = nil
		if proto.hasNumber {
			number = proto.number
		}

		var name: String? = nil
		if proto.hasName {
			name = proto.name
		}

		var avatar: SSKProtoContactDetailsAvatar? = nil
		if proto.hasAvatar {
			avatar = try SSKProtoContactDetailsAvatar.parseProto(proto.avatar)
		}

		var color: String? = nil
		if proto.hasColor {
			color = proto.color
		}

		var verified: SSKProtoVerified? = nil
		if proto.hasVerified {
			verified = try SSKProtoVerified.parseProto(proto.verified)
		}

		var profileKey: Data? = nil
		if proto.hasProfileKey {
			profileKey = proto.profileKey
		}

		var blocked: Bool = false
		if proto.hasBlocked {
			blocked = proto.blocked
		}

		var expireTimer: UInt32 = 0
		if proto.hasExpireTimer {
			expireTimer = proto.expireTimer
		}

		// MARK: - Begin Validation Logic for SSKProtoContactDetails -

        guard proto.hasNumber else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: number")
        }

		// MARK: - End Validation Logic for SSKProtoContactDetails -

		let result = SSKProtoContactDetails(number: number,
		                                    name: name,
		                                    avatar: avatar,
		                                    color: color,
		                                    verified: verified,
		                                    profileKey: profileKey,
		                                    blocked: blocked,
		                                    expireTimer: expireTimer)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_ContactDetails {
		let proto = SignalServiceProtos_ContactDetails.with { (builder) in
			if let number = self.number {
				builder.number = number
			}

			if let name = self.name {
				builder.name = name
			}

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			if let color = self.color {
				builder.color = color
			}

			if let verified = self.verified {
				builder.verified = verified.asProtobuf
			}

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}

			builder.blocked = self.blocked

			builder.expireTimer = self.expireTimer
		}

		return proto
	}
}

// MARK: - SSKProtoGroupDetailsAvatar

@objc public class SSKProtoGroupDetailsAvatar: NSObject {

	@objc public let contentType: String?
	@objc public let length: UInt32

	@objc public init(contentType: String?,
	                  length: UInt32) {
		self.contentType = contentType
		self.length = length
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupDetailsAvatar {
		let proto = try SignalServiceProtos_GroupDetails.Avatar(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupDetails.Avatar) throws -> SSKProtoGroupDetailsAvatar {
		var contentType: String? = nil
		if proto.hasContentType {
			contentType = proto.contentType
		}

		var length: UInt32 = 0
		if proto.hasLength {
			length = proto.length
		}

		// MARK: - Begin Validation Logic for SSKProtoGroupDetailsAvatar -

		// MARK: - End Validation Logic for SSKProtoGroupDetailsAvatar -

		let result = SSKProtoGroupDetailsAvatar(contentType: contentType,
		                                        length: length)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_GroupDetails.Avatar {
		let proto = SignalServiceProtos_GroupDetails.Avatar.with { (builder) in
			if let contentType = self.contentType {
				builder.contentType = contentType
			}

			builder.length = self.length
		}

		return proto
	}
}

// MARK: - SSKProtoGroupDetails

@objc public class SSKProtoGroupDetails: NSObject {

	@objc public let id: Data?
	@objc public let name: String?
	@objc public let members: [String]
	@objc public let avatar: SSKProtoGroupDetailsAvatar?
	@objc public let active: Bool
	@objc public let expireTimer: UInt32
	@objc public let color: String?

	@objc public init(id: Data?,
	                  name: String?,
	                  members: [String],
	                  avatar: SSKProtoGroupDetailsAvatar?,
	                  active: Bool,
	                  expireTimer: UInt32,
	                  color: String?) {
		self.id = id
		self.name = name
		self.members = members
		self.avatar = avatar
		self.active = active
		self.expireTimer = expireTimer
		self.color = color
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SSKProtoGroupDetails {
		let proto = try SignalServiceProtos_GroupDetails(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: SignalServiceProtos_GroupDetails) throws -> SSKProtoGroupDetails {
		var id: Data? = nil
		if proto.hasID {
			id = proto.id
		}

		var name: String? = nil
		if proto.hasName {
			name = proto.name
		}

		var members: [String] = []
		for item in proto.members {
			let wrapped = item
			members.append(wrapped)
		}

		var avatar: SSKProtoGroupDetailsAvatar? = nil
		if proto.hasAvatar {
			avatar = try SSKProtoGroupDetailsAvatar.parseProto(proto.avatar)
		}

		var active: Bool = true
		if proto.hasActive {
			active = proto.active
		}

		var expireTimer: UInt32 = 0
		if proto.hasExpireTimer {
			expireTimer = proto.expireTimer
		}

		var color: String? = nil
		if proto.hasColor {
			color = proto.color
		}

		// MARK: - Begin Validation Logic for SSKProtoGroupDetails -

        guard proto.hasID else {
            throw SSKProtoError.invalidProtobuf(description: "\(logTag) missing required field: id")
        }

		// MARK: - End Validation Logic for SSKProtoGroupDetails -

		let result = SSKProtoGroupDetails(id: id,
		                                  name: name,
		                                  members: members,
		                                  avatar: avatar,
		                                  active: active,
		                                  expireTimer: expireTimer,
		                                  color: color)
		return result
	}

	fileprivate var asProtobuf: SignalServiceProtos_GroupDetails {
		let proto = SignalServiceProtos_GroupDetails.with { (builder) in
			if let id = self.id {
				builder.id = id
			}

			if let name = self.name {
				builder.name = name
			}

			var membersUnwrapped = [String]()
			for item in members {
				membersUnwrapped.append(item)
			}
			builder.members = membersUnwrapped

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			builder.active = self.active

			builder.expireTimer = self.expireTimer

			if let color = self.color {
				builder.color = color
			}
		}

		return proto
	}
}
