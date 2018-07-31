//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - SSKProtoEnvelope

@objc public class SSKProtoEnvelope: NSObject {

	public enum SSKProtoEnvelopeError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoEnvelope_Type

	@objc public enum SSKProtoEnvelope_Type: Int32 {
		case unknown = 0
		case ciphertext = 1
		case keyExchange = 2
		case prekeyBundle = 3
		case receipt = 5
	}

	private func SSKProtoEnvelope_TypeWrap(value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelope_Type {
		switch value {
			case .unknown: return .unknown
			case .ciphertext: return .ciphertext
			case .keyExchange: return .keyExchange
			case .prekeyBundle: return .prekeyBundle
			case .receipt: return .receipt
		}
	}

	private func SSKProtoEnvelope_TypeUnwrap(value: SSKProtoEnvelope_Type) -> SignalServiceProtos_Envelope.TypeEnum {
		switch value {
			case .unknown: return .unknown
			case .ciphertext: return .ciphertext
			case .keyExchange: return .keyExchange
			case .prekeyBundle: return .prekeyBundle
			case .receipt: return .receipt
		}
	}

	@objc public let type: SSKProtoEnvelope_Type
	@objc public let relay: String?
	@objc public let source: String?
	@objc public let timestamp: UInt64
	@objc public let sourceDevice: UInt32
	@objc public let legacyMessage: Data?
	@objc public let content: Data?

	@objc public init(type: SSKProtoEnvelope_Type, relay: String?, source: String?, timestamp: UInt64, sourceDevice: UInt32, legacyMessage: Data?, content: Data?) {
		self.type = type
		self.relay = relay
		self.source = source
		self.timestamp = timestamp
		self.sourceDevice = sourceDevice
		self.legacyMessage = legacyMessage
		self.content = content
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_Envelope {
	}
}

// MARK: - SSKProtoContent

@objc public class SSKProtoContent: NSObject {

	public enum SSKProtoContentError: Error {
	    case invalidProtobuf(description: String)
	}

	@objc public let dataMessage: SSKProtoDataMessage?
	@objc public let callMessage: SSKProtoCallMessage?
	@objc public let syncMessage: SSKProtoSyncMessage?
	@objc public let receiptMessage: SSKProtoReceiptMessage?
	@objc public let nullMessage: SSKProtoNullMessage?

	@objc public init(dataMessage: SSKProtoDataMessage?, callMessage: SSKProtoCallMessage?, syncMessage: SSKProtoSyncMessage?, receiptMessage: SSKProtoReceiptMessage?, nullMessage: SSKProtoNullMessage?) {
		self.dataMessage = dataMessage
		self.callMessage = callMessage
		self.syncMessage = syncMessage
		self.receiptMessage = receiptMessage
		self.nullMessage = nullMessage
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_Content {
	}
}

// MARK: - SSKProtoCallMessage

@objc public class SSKProtoCallMessage: NSObject {

	public enum SSKProtoCallMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoCallMessage_Offer

	@objc public class SSKProtoCallMessage_Offer: NSObject {

		@objc public let id: UInt64
		@objc public let sessionDescription: String?

		@objc public init(id: UInt64, sessionDescription: String?) {
			self.id = id
			self.sessionDescription = sessionDescription
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_CallMessage.Offer {
		}
	}

	// MARK: - SSKProtoCallMessage_Answer

	@objc public class SSKProtoCallMessage_Answer: NSObject {

		@objc public let id: UInt64
		@objc public let sessionDescription: String?

		@objc public init(id: UInt64, sessionDescription: String?) {
			self.id = id
			self.sessionDescription = sessionDescription
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_CallMessage.Answer {
		}
	}

	// MARK: - SSKProtoCallMessage_IceUpdate

	@objc public class SSKProtoCallMessage_IceUpdate: NSObject {

		@objc public let id: UInt64
		@objc public let sdpMLineIndex: UInt32
		@objc public let sdpMid: String?
		@objc public let sdp: String?

		@objc public init(id: UInt64, sdpMLineIndex: UInt32, sdpMid: String?, sdp: String?) {
			self.id = id
			self.sdpMLineIndex = sdpMLineIndex
			self.sdpMid = sdpMid
			self.sdp = sdp
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_CallMessage.IceUpdate {
		}
	}

	// MARK: - SSKProtoCallMessage_Busy

	@objc public class SSKProtoCallMessage_Busy: NSObject {

		@objc public let id: UInt64

		@objc public init(id: UInt64) {
			self.id = id
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_CallMessage.Busy {
		}
	}

	// MARK: - SSKProtoCallMessage_Hangup

	@objc public class SSKProtoCallMessage_Hangup: NSObject {

		@objc public let id: UInt64

		@objc public init(id: UInt64) {
			self.id = id
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_CallMessage.Hangup {
		}
	}

	@objc public let offer: SSKProtoCallMessage_Offer?
	@objc public let iceUpdate: [SSKProtoCallMessage_IceUpdate]
	@objc public let answer: SSKProtoCallMessage_Answer?
	@objc public let busy: SSKProtoCallMessage_Busy?
	@objc public let hangup: SSKProtoCallMessage_Hangup?
	@objc public let profileKey: Data?

	@objc public init(offer: SSKProtoCallMessage_Offer?, iceUpdate: [SSKProtoCallMessage_IceUpdate], answer: SSKProtoCallMessage_Answer?, busy: SSKProtoCallMessage_Busy?, hangup: SSKProtoCallMessage_Hangup?, profileKey: Data?) {
		self.offer = offer
		self.iceUpdate = iceUpdate
		self.answer = answer
		self.busy = busy
		self.hangup = hangup
		self.profileKey = profileKey
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_CallMessage {
	}
}

// MARK: - SSKProtoDataMessage

@objc public class SSKProtoDataMessage: NSObject {

	public enum SSKProtoDataMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoDataMessage_Flags

	@objc public enum SSKProtoDataMessage_Flags: Int32 {
		case endSession = 1
		case expirationTimerUpdate = 2
		case profileKeyUpdate = 4
	}

	private func SSKProtoDataMessage_FlagsWrap(value: SignalServiceProtos_DataMessage.FlagsEnum) -> SSKProtoDataMessage_Flags {
		switch value {
			case .endSession: return .endSession
			case .expirationTimerUpdate: return .expirationTimerUpdate
			case .profileKeyUpdate: return .profileKeyUpdate
		}
	}

	private func SSKProtoDataMessage_FlagsUnwrap(value: SSKProtoDataMessage_Flags) -> SignalServiceProtos_DataMessage.FlagsEnum {
		switch value {
			case .endSession: return .endSession
			case .expirationTimerUpdate: return .expirationTimerUpdate
			case .profileKeyUpdate: return .profileKeyUpdate
		}
	}

	// MARK: - SSKProtoDataMessage_Quote

	@objc public class SSKProtoDataMessage_Quote: NSObject {

		// MARK: - SSKProtoDataMessage_Quote_QuotedAttachment

		@objc public class SSKProtoDataMessage_Quote_QuotedAttachment: NSObject {

			// MARK: - SSKProtoDataMessage_Quote_QuotedAttachment_Flags

			@objc public enum SSKProtoDataMessage_Quote_QuotedAttachment_Flags: Int32 {
				case voiceMessage = 1
			}

			private func SSKProtoDataMessage_Quote_QuotedAttachment_FlagsWrap(value: SignalServiceProtos_DataMessage.Quote.QuotedAttachment.FlagsEnum) -> SSKProtoDataMessage_Quote_QuotedAttachment_Flags {
				switch value {
					case .voiceMessage: return .voiceMessage
				}
			}

			private func SSKProtoDataMessage_Quote_QuotedAttachment_FlagsUnwrap(value: SSKProtoDataMessage_Quote_QuotedAttachment_Flags) -> SignalServiceProtos_DataMessage.Quote.QuotedAttachment.FlagsEnum {
				switch value {
					case .voiceMessage: return .voiceMessage
				}
			}

			@objc public let contentType: String?
			@objc public let thumbnail: SSKProtoAttachmentPointer?
			@objc public let fileName: String?
			@objc public let flags: UInt32

			@objc public init(contentType: String?, thumbnail: SSKProtoAttachmentPointer?, fileName: String?, flags: UInt32) {
				self.contentType = contentType
				self.thumbnail = thumbnail
				self.fileName = fileName
				self.flags = flags
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Quote.QuotedAttachment {
			}
		}

		@objc public let id: UInt64
		@objc public let text: String?
		@objc public let author: String?
		@objc public let attachments: [SSKProtoDataMessage_Quote_QuotedAttachment]

		@objc public init(id: UInt64, text: String?, author: String?, attachments: [SSKProtoDataMessage_Quote_QuotedAttachment]) {
			self.id = id
			self.text = text
			self.author = author
			self.attachments = attachments
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_DataMessage.Quote {
		}
	}

	// MARK: - SSKProtoDataMessage_Contact

	@objc public class SSKProtoDataMessage_Contact: NSObject {

		// MARK: - SSKProtoDataMessage_Contact_Name

		@objc public class SSKProtoDataMessage_Contact_Name: NSObject {

			@objc public let givenName: String?
			@objc public let prefix: String?
			@objc public let familyName: String?
			@objc public let middleName: String?
			@objc public let suffix: String?
			@objc public let displayName: String?

			@objc public init(givenName: String?, prefix: String?, familyName: String?, middleName: String?, suffix: String?, displayName: String?) {
				self.givenName = givenName
				self.prefix = prefix
				self.familyName = familyName
				self.middleName = middleName
				self.suffix = suffix
				self.displayName = displayName
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Contact.Name {
			}
		}

		// MARK: - SSKProtoDataMessage_Contact_Phone

		@objc public class SSKProtoDataMessage_Contact_Phone: NSObject {

			// MARK: - SSKProtoDataMessage_Contact_Phone_Type

			@objc public enum SSKProtoDataMessage_Contact_Phone_Type: Int32 {
				case home = 1
				case mobile = 2
				case work = 3
				case custom = 4
			}

			private func SSKProtoDataMessage_Contact_Phone_TypeWrap(value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SSKProtoDataMessage_Contact_Phone_Type {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_Phone_TypeUnwrap(value: SSKProtoDataMessage_Contact_Phone_Type) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			@objc public let value: String?
			@objc public let label: String?
			@objc public let type: SSKProtoDataMessage_Contact_Phone_Type

			@objc public init(value: String?, label: String?, type: SSKProtoDataMessage_Contact_Phone_Type) {
				self.value = value
				self.label = label
				self.type = type
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Contact.Phone {
			}
		}

		// MARK: - SSKProtoDataMessage_Contact_Email

		@objc public class SSKProtoDataMessage_Contact_Email: NSObject {

			// MARK: - SSKProtoDataMessage_Contact_Email_Type

			@objc public enum SSKProtoDataMessage_Contact_Email_Type: Int32 {
				case home = 1
				case mobile = 2
				case work = 3
				case custom = 4
			}

			private func SSKProtoDataMessage_Contact_Email_TypeWrap(value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SSKProtoDataMessage_Contact_Email_Type {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_Email_TypeUnwrap(value: SSKProtoDataMessage_Contact_Email_Type) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			@objc public let value: String?
			@objc public let label: String?
			@objc public let type: SSKProtoDataMessage_Contact_Email_Type

			@objc public init(value: String?, label: String?, type: SSKProtoDataMessage_Contact_Email_Type) {
				self.value = value
				self.label = label
				self.type = type
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Contact.Email {
			}
		}

		// MARK: - SSKProtoDataMessage_Contact_PostalAddress

		@objc public class SSKProtoDataMessage_Contact_PostalAddress: NSObject {

			// MARK: - SSKProtoDataMessage_Contact_PostalAddress_Type

			@objc public enum SSKProtoDataMessage_Contact_PostalAddress_Type: Int32 {
				case home = 1
				case work = 2
				case custom = 3
			}

			private func SSKProtoDataMessage_Contact_PostalAddress_TypeWrap(value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SSKProtoDataMessage_Contact_PostalAddress_Type {
				switch value {
					case .home: return .home
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_PostalAddress_TypeUnwrap(value: SSKProtoDataMessage_Contact_PostalAddress_Type) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
				switch value {
					case .home: return .home
					case .work: return .work
					case .custom: return .custom
				}
			}

			@objc public let type: SSKProtoDataMessage_Contact_PostalAddress_Type
			@objc public let street: String?
			@objc public let label: String?
			@objc public let neighborhood: String?
			@objc public let pobox: String?
			@objc public let region: String?
			@objc public let city: String?
			@objc public let country: String?
			@objc public let postcode: String?

			@objc public init(type: SSKProtoDataMessage_Contact_PostalAddress_Type, street: String?, label: String?, neighborhood: String?, pobox: String?, region: String?, city: String?, country: String?, postcode: String?) {
				self.type = type
				self.street = street
				self.label = label
				self.neighborhood = neighborhood
				self.pobox = pobox
				self.region = region
				self.city = city
				self.country = country
				self.postcode = postcode
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Contact.PostalAddress {
			}
		}

		// MARK: - SSKProtoDataMessage_Contact_Avatar

		@objc public class SSKProtoDataMessage_Contact_Avatar: NSObject {

			@objc public let avatar: SSKProtoAttachmentPointer?
			@objc public let isProfile: bool?

			@objc public init(avatar: SSKProtoAttachmentPointer?, isProfile: bool?) {
				self.avatar = avatar
				self.isProfile = isProfile
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
			}

			private var asProtobuf: SignalServiceProtos_DataMessage.Contact.Avatar {
			}
		}

		@objc public let name: SSKProtoDataMessage_Contact_Name?
		@objc public let number: [SSKProtoDataMessage_Contact_Phone]
		@objc public let address: [SSKProtoDataMessage_Contact_PostalAddress]
		@objc public let email: [SSKProtoDataMessage_Contact_Email]
		@objc public let organization: String?
		@objc public let avatar: SSKProtoDataMessage_Contact_Avatar?

		@objc public init(name: SSKProtoDataMessage_Contact_Name?, number: [SSKProtoDataMessage_Contact_Phone], address: [SSKProtoDataMessage_Contact_PostalAddress], email: [SSKProtoDataMessage_Contact_Email], organization: String?, avatar: SSKProtoDataMessage_Contact_Avatar?) {
			self.name = name
			self.number = number
			self.address = address
			self.email = email
			self.organization = organization
			self.avatar = avatar
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_DataMessage.Contact {
		}
	}

	@objc public let body: String?
	@objc public let group: SSKProtoGroupContext?
	@objc public let attachments: [SSKProtoAttachmentPointer]
	@objc public let expireTimer: UInt32
	@objc public let flags: UInt32
	@objc public let timestamp: UInt64
	@objc public let profileKey: Data?
	@objc public let contact: [SSKProtoDataMessage_Contact]
	@objc public let quote: SSKProtoDataMessage_Quote?

	@objc public init(body: String?, group: SSKProtoGroupContext?, attachments: [SSKProtoAttachmentPointer], expireTimer: UInt32, flags: UInt32, timestamp: UInt64, profileKey: Data?, contact: [SSKProtoDataMessage_Contact], quote: SSKProtoDataMessage_Quote?) {
		self.body = body
		self.group = group
		self.attachments = attachments
		self.expireTimer = expireTimer
		self.flags = flags
		self.timestamp = timestamp
		self.profileKey = profileKey
		self.contact = contact
		self.quote = quote
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_DataMessage {
	}
}

// MARK: - SSKProtoNullMessage

@objc public class SSKProtoNullMessage: NSObject {

	public enum SSKProtoNullMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	@objc public let padding: Data?

	@objc public init(padding: Data?) {
		self.padding = padding
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_NullMessage {
	}
}

// MARK: - SSKProtoReceiptMessage

@objc public class SSKProtoReceiptMessage: NSObject {

	public enum SSKProtoReceiptMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoReceiptMessage_Type

	@objc public enum SSKProtoReceiptMessage_Type: Int32 {
		case delivery = 0
		case read = 1
	}

	private func SSKProtoReceiptMessage_TypeWrap(value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SSKProtoReceiptMessage_Type {
		switch value {
			case .delivery: return .delivery
			case .read: return .read
		}
	}

	private func SSKProtoReceiptMessage_TypeUnwrap(value: SSKProtoReceiptMessage_Type) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
		switch value {
			case .delivery: return .delivery
			case .read: return .read
		}
	}

	@objc public let type: SSKProtoReceiptMessage_Type
	@objc public let timestamp: [UInt64]

	@objc public init(type: SSKProtoReceiptMessage_Type, timestamp: [UInt64]) {
		self.type = type
		self.timestamp = timestamp
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_ReceiptMessage {
	}
}

// MARK: - SSKProtoVerified

@objc public class SSKProtoVerified: NSObject {

	public enum SSKProtoVerifiedError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoVerified_State

	@objc public enum SSKProtoVerified_State: Int32 {
		case default = 0
		case verified = 1
		case unverified = 2
	}

	private func SSKProtoVerified_StateWrap(value: SignalServiceProtos_Verified.StateEnum) -> SSKProtoVerified_State {
		switch value {
			case .default: return .default
			case .verified: return .verified
			case .unverified: return .unverified
		}
	}

	private func SSKProtoVerified_StateUnwrap(value: SSKProtoVerified_State) -> SignalServiceProtos_Verified.StateEnum {
		switch value {
			case .default: return .default
			case .verified: return .verified
			case .unverified: return .unverified
		}
	}

	@objc public let destination: String?
	@objc public let state: SSKProtoVerified_State
	@objc public let identityKey: Data?
	@objc public let nullMessage: Data?

	@objc public init(destination: String?, state: SSKProtoVerified_State, identityKey: Data?, nullMessage: Data?) {
		self.destination = destination
		self.state = state
		self.identityKey = identityKey
		self.nullMessage = nullMessage
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_Verified {
	}
}

// MARK: - SSKProtoSyncMessage

@objc public class SSKProtoSyncMessage: NSObject {

	public enum SSKProtoSyncMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoSyncMessage_Sent

	@objc public class SSKProtoSyncMessage_Sent: NSObject {

		@objc public let destination: String?
		@objc public let message: SSKProtoDataMessage?
		@objc public let timestamp: UInt64
		@objc public let expirationStartTimestamp: UInt64

		@objc public init(destination: String?, message: SSKProtoDataMessage?, timestamp: UInt64, expirationStartTimestamp: UInt64) {
			self.destination = destination
			self.message = message
			self.timestamp = timestamp
			self.expirationStartTimestamp = expirationStartTimestamp
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Sent {
		}
	}

	// MARK: - SSKProtoSyncMessage_Contacts

	@objc public class SSKProtoSyncMessage_Contacts: NSObject {

		@objc public let blob: SSKProtoAttachmentPointer?
		@objc public let isComplete: bool?

		@objc public init(blob: SSKProtoAttachmentPointer?, isComplete: bool?) {
			self.blob = blob
			self.isComplete = isComplete
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Contacts {
		}
	}

	// MARK: - SSKProtoSyncMessage_Groups

	@objc public class SSKProtoSyncMessage_Groups: NSObject {

		@objc public let blob: SSKProtoAttachmentPointer?

		@objc public init(blob: SSKProtoAttachmentPointer?) {
			self.blob = blob
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Groups {
		}
	}

	// MARK: - SSKProtoSyncMessage_Blocked

	@objc public class SSKProtoSyncMessage_Blocked: NSObject {

		@objc public let numbers: [String]

		@objc public init(numbers: [String]) {
			self.numbers = numbers
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Blocked {
		}
	}

	// MARK: - SSKProtoSyncMessage_Request

	@objc public class SSKProtoSyncMessage_Request: NSObject {

		// MARK: - SSKProtoSyncMessage_Request_Type

		@objc public enum SSKProtoSyncMessage_Request_Type: Int32 {
			case unknown = 0
			case contacts = 1
			case groups = 2
			case blocked = 3
			case configuration = 4
		}

		private func SSKProtoSyncMessage_Request_TypeWrap(value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SSKProtoSyncMessage_Request_Type {
			switch value {
				case .unknown: return .unknown
				case .contacts: return .contacts
				case .groups: return .groups
				case .blocked: return .blocked
				case .configuration: return .configuration
			}
		}

		private func SSKProtoSyncMessage_Request_TypeUnwrap(value: SSKProtoSyncMessage_Request_Type) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
			switch value {
				case .unknown: return .unknown
				case .contacts: return .contacts
				case .groups: return .groups
				case .blocked: return .blocked
				case .configuration: return .configuration
			}
		}

		@objc public let type: SSKProtoSyncMessage_Request_Type

		@objc public init(type: SSKProtoSyncMessage_Request_Type) {
			self.type = type
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Request {
		}
	}

	// MARK: - SSKProtoSyncMessage_Read

	@objc public class SSKProtoSyncMessage_Read: NSObject {

		@objc public let sender: String?
		@objc public let timestamp: UInt64

		@objc public init(sender: String?, timestamp: UInt64) {
			self.sender = sender
			self.timestamp = timestamp
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Read {
		}
	}

	// MARK: - SSKProtoSyncMessage_Configuration

	@objc public class SSKProtoSyncMessage_Configuration: NSObject {

		@objc public let readReceipts: bool?

		@objc public init(readReceipts: bool?) {
			self.readReceipts = readReceipts
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_SyncMessage.Configuration {
		}
	}

	@objc public let sent: SSKProtoSyncMessage_Sent?
	@objc public let groups: SSKProtoSyncMessage_Groups?
	@objc public let contacts: SSKProtoSyncMessage_Contacts?
	@objc public let read: [SSKProtoSyncMessage_Read]
	@objc public let request: SSKProtoSyncMessage_Request?
	@objc public let verified: SSKProtoVerified?
	@objc public let blocked: SSKProtoSyncMessage_Blocked?
	@objc public let configuration: SSKProtoSyncMessage_Configuration?
	@objc public let padding: Data?

	@objc public init(sent: SSKProtoSyncMessage_Sent?, groups: SSKProtoSyncMessage_Groups?, contacts: SSKProtoSyncMessage_Contacts?, read: [SSKProtoSyncMessage_Read], request: SSKProtoSyncMessage_Request?, verified: SSKProtoVerified?, blocked: SSKProtoSyncMessage_Blocked?, configuration: SSKProtoSyncMessage_Configuration?, padding: Data?) {
		self.sent = sent
		self.groups = groups
		self.contacts = contacts
		self.read = read
		self.request = request
		self.verified = verified
		self.blocked = blocked
		self.configuration = configuration
		self.padding = padding
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_SyncMessage {
	}
}

// MARK: - SSKProtoAttachmentPointer

@objc public class SSKProtoAttachmentPointer: NSObject {

	public enum SSKProtoAttachmentPointerError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoAttachmentPointer_Flags

	@objc public enum SSKProtoAttachmentPointer_Flags: Int32 {
		case voiceMessage = 1
	}

	private func SSKProtoAttachmentPointer_FlagsWrap(value: SignalServiceProtos_AttachmentPointer.FlagsEnum) -> SSKProtoAttachmentPointer_Flags {
		switch value {
			case .voiceMessage: return .voiceMessage
		}
	}

	private func SSKProtoAttachmentPointer_FlagsUnwrap(value: SSKProtoAttachmentPointer_Flags) -> SignalServiceProtos_AttachmentPointer.FlagsEnum {
		switch value {
			case .voiceMessage: return .voiceMessage
		}
	}

	@objc public let height: UInt32
	@objc public let id: fixed64?
	@objc public let key: Data?
	@objc public let contentType: String?
	@objc public let thumbnail: Data?
	@objc public let size: UInt32
	@objc public let fileName: String?
	@objc public let digest: Data?
	@objc public let width: UInt32
	@objc public let flags: UInt32

	@objc public init(height: UInt32, id: fixed64?, key: Data?, contentType: String?, thumbnail: Data?, size: UInt32, fileName: String?, digest: Data?, width: UInt32, flags: UInt32) {
		self.height = height
		self.id = id
		self.key = key
		self.contentType = contentType
		self.thumbnail = thumbnail
		self.size = size
		self.fileName = fileName
		self.digest = digest
		self.width = width
		self.flags = flags
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_AttachmentPointer {
	}
}

// MARK: - SSKProtoGroupContext

@objc public class SSKProtoGroupContext: NSObject {

	public enum SSKProtoGroupContextError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoGroupContext_Type

	@objc public enum SSKProtoGroupContext_Type: Int32 {
		case unknown = 0
		case update = 1
		case deliver = 2
		case quit = 3
		case requestInfo = 4
	}

	private func SSKProtoGroupContext_TypeWrap(value: SignalServiceProtos_GroupContext.TypeEnum) -> SSKProtoGroupContext_Type {
		switch value {
			case .unknown: return .unknown
			case .update: return .update
			case .deliver: return .deliver
			case .quit: return .quit
			case .requestInfo: return .requestInfo
		}
	}

	private func SSKProtoGroupContext_TypeUnwrap(value: SSKProtoGroupContext_Type) -> SignalServiceProtos_GroupContext.TypeEnum {
		switch value {
			case .unknown: return .unknown
			case .update: return .update
			case .deliver: return .deliver
			case .quit: return .quit
			case .requestInfo: return .requestInfo
		}
	}

	@objc public let id: Data?
	@objc public let name: String?
	@objc public let type: SSKProtoGroupContext_Type
	@objc public let avatar: SSKProtoAttachmentPointer?
	@objc public let members: [String]

	@objc public init(id: Data?, name: String?, type: SSKProtoGroupContext_Type, avatar: SSKProtoAttachmentPointer?, members: [String]) {
		self.id = id
		self.name = name
		self.type = type
		self.avatar = avatar
		self.members = members
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_GroupContext {
	}
}

// MARK: - SSKProtoContactDetails

@objc public class SSKProtoContactDetails: NSObject {

	public enum SSKProtoContactDetailsError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoContactDetails_Avatar

	@objc public class SSKProtoContactDetails_Avatar: NSObject {

		@objc public let contentType: String?
		@objc public let length: UInt32

		@objc public init(contentType: String?, length: UInt32) {
			self.contentType = contentType
			self.length = length
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_ContactDetails.Avatar {
		}
	}

	@objc public let number: String?
	@objc public let avatar: SSKProtoContactDetails_Avatar?
	@objc public let name: String?
	@objc public let verified: SSKProtoVerified?
	@objc public let color: String?
	@objc public let blocked: bool?
	@objc public let profileKey: Data?
	@objc public let expireTimer: UInt32

	@objc public init(number: String?, avatar: SSKProtoContactDetails_Avatar?, name: String?, verified: SSKProtoVerified?, color: String?, blocked: bool?, profileKey: Data?, expireTimer: UInt32) {
		self.number = number
		self.avatar = avatar
		self.name = name
		self.verified = verified
		self.color = color
		self.blocked = blocked
		self.profileKey = profileKey
		self.expireTimer = expireTimer
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_ContactDetails {
	}
}

// MARK: - SSKProtoGroupDetails

@objc public class SSKProtoGroupDetails: NSObject {

	public enum SSKProtoGroupDetailsError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoGroupDetails_Avatar

	@objc public class SSKProtoGroupDetails_Avatar: NSObject {

		@objc public let contentType: String?
		@objc public let length: UInt32

		@objc public init(contentType: String?, length: UInt32) {
			self.contentType = contentType
			self.length = length
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		private var asProtobuf: SignalServiceProtos_GroupDetails.Avatar {
		}
	}

	@objc public let id: Data?
	@objc public let members: [String]
	@objc public let name: String?
	@objc public let active: bool?
	@objc public let avatar: SSKProtoGroupDetails_Avatar?
	@objc public let color: String?
	@objc public let expireTimer: UInt32

	@objc public init(id: Data?, members: [String], name: String?, active: bool?, avatar: SSKProtoGroupDetails_Avatar?, color: String?, expireTimer: UInt32) {
		self.id = id
		self.members = members
		self.name = name
		self.active = active
		self.avatar = avatar
		self.color = color
		self.expireTimer = expireTimer
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	private var asProtobuf: SignalServiceProtos_GroupDetails {
	}
}
