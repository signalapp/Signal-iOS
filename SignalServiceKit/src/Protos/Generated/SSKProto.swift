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

	private func SSKProtoEnvelope_TypeWrap(_ value: SignalServiceProtos_Envelope.TypeEnum) -> SSKProtoEnvelope_Type {
		switch value {
			case .unknown: return .unknown
			case .ciphertext: return .ciphertext
			case .keyExchange: return .keyExchange
			case .prekeyBundle: return .prekeyBundle
			case .receipt: return .receipt
		}
	}

	private func SSKProtoEnvelope_TypeUnwrap(_ value: SSKProtoEnvelope_Type) -> SignalServiceProtos_Envelope.TypeEnum {
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

	fileprivate var asProtobuf: SignalServiceProtos_Envelope {
		let proto = SignalServiceProtos_Envelope.with { (builder) in
			builder.type = SSKProtoEnvelope_TypeUnwrap(self.type)

			if let relay = self.relay {
				builder.relay = relay
			}

			if let source = self.source {
				builder.source = source
			}

			builder.timestamp = self.timestamp

			builder.sourceDevice = self.sourceDevice

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

	fileprivate var asProtobuf: SignalServiceProtos_Content {
		let proto = SignalServiceProtos_Content.with { (builder) in
			if let dataMessage = self.dataMessage {
				builder.dataMessage = dataMessage.asProtobuf
			}

			if let callMessage = self.callMessage {
				builder.callMessage = callMessage.asProtobuf
			}

			if let syncMessage = self.syncMessage {
				builder.syncMessage = syncMessage.asProtobuf
			}

			if let receiptMessage = self.receiptMessage {
				builder.receiptMessage = receiptMessage.asProtobuf
			}

			if let nullMessage = self.nullMessage {
				builder.nullMessage = nullMessage.asProtobuf
			}
		}

		return proto
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

	// MARK: - SSKProtoCallMessage_IceUpdate

	@objc public class SSKProtoCallMessage_IceUpdate: NSObject {

		@objc public let id: UInt64
		@objc public let sdpMlineIndex: UInt32
		@objc public let sdpMid: String?
		@objc public let sdp: String?

		@objc public init(id: UInt64, sdpMlineIndex: UInt32, sdpMid: String?, sdp: String?) {
			self.id = id
			self.sdpMlineIndex = sdpMlineIndex
			self.sdpMid = sdpMid
			self.sdp = sdp
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		fileprivate var asProtobuf: SignalServiceProtos_CallMessage.IceUpdate {
			let proto = SignalServiceProtos_CallMessage.IceUpdate.with { (builder) in
				builder.id = self.id

				builder.sdpMlineIndex = self.sdpMlineIndex

				if let sdpMid = self.sdpMid {
					builder.sdpMid = sdpMid
				}

				if let sdp = self.sdp {
					builder.sdp = sdp
				}
			}

			return proto
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

		fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Busy {
			let proto = SignalServiceProtos_CallMessage.Busy.with { (builder) in
				builder.id = self.id
			}

			return proto
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

		fileprivate var asProtobuf: SignalServiceProtos_CallMessage.Hangup {
			let proto = SignalServiceProtos_CallMessage.Hangup.with { (builder) in
				builder.id = self.id
			}

			return proto
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

	fileprivate var asProtobuf: SignalServiceProtos_CallMessage {
		let proto = SignalServiceProtos_CallMessage.with { (builder) in
			if let offer = self.offer {
				builder.offer = offer.asProtobuf
			}

			var iceUpdateUnwrapped = [SignalServiceProtos_CallMessage.IceUpdate]()
			for item in iceUpdate {
				iceUpdateUnwrapped.append(item.asProtobuf)
			}
			builder.iceUpdate = iceUpdateUnwrapped

			if let answer = self.answer {
				builder.answer = answer.asProtobuf
			}

			if let busy = self.busy {
				builder.busy = busy.asProtobuf
			}

			if let hangup = self.hangup {
				builder.hangup = hangup.asProtobuf
			}

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}
		}

		return proto
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

	private func SSKProtoDataMessage_FlagsWrap(_ value: SignalServiceProtos_DataMessage.Flags) -> SSKProtoDataMessage_Flags {
		switch value {
			case .endSession: return .endSession
			case .expirationTimerUpdate: return .expirationTimerUpdate
			case .profileKeyUpdate: return .profileKeyUpdate
		}
	}

	private func SSKProtoDataMessage_FlagsUnwrap(_ value: SSKProtoDataMessage_Flags) -> SignalServiceProtos_DataMessage.Flags {
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

			private func SSKProtoDataMessage_Quote_QuotedAttachment_FlagsWrap(_ value: SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags) -> SSKProtoDataMessage_Quote_QuotedAttachment_Flags {
				switch value {
					case .voiceMessage: return .voiceMessage
				}
			}

			private func SSKProtoDataMessage_Quote_QuotedAttachment_FlagsUnwrap(_ value: SSKProtoDataMessage_Quote_QuotedAttachment_Flags) -> SignalServiceProtos_DataMessage.Quote.QuotedAttachment.Flags {
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

			fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote.QuotedAttachment {
				let proto = SignalServiceProtos_DataMessage.Quote.QuotedAttachment.with { (builder) in
					if let contentType = self.contentType {
						builder.contentType = contentType
					}

					if let thumbnail = self.thumbnail {
						builder.thumbnail = thumbnail.asProtobuf
					}

					if let fileName = self.fileName {
						builder.fileName = fileName
					}

					builder.flags = self.flags
				}

				return proto
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

		fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Quote {
			let proto = SignalServiceProtos_DataMessage.Quote.with { (builder) in
				builder.id = self.id

				if let text = self.text {
					builder.text = text
				}

				if let author = self.author {
					builder.author = author
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

			fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Name {
				let proto = SignalServiceProtos_DataMessage.Contact.Name.with { (builder) in
					if let givenName = self.givenName {
						builder.givenName = givenName
					}

					if let prefix = self.prefix {
						builder.prefix = prefix
					}

					if let familyName = self.familyName {
						builder.familyName = familyName
					}

					if let middleName = self.middleName {
						builder.middleName = middleName
					}

					if let suffix = self.suffix {
						builder.suffix = suffix
					}

					if let displayName = self.displayName {
						builder.displayName = displayName
					}
				}

				return proto
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

			private func SSKProtoDataMessage_Contact_Phone_TypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum) -> SSKProtoDataMessage_Contact_Phone_Type {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_Phone_TypeUnwrap(_ value: SSKProtoDataMessage_Contact_Phone_Type) -> SignalServiceProtos_DataMessage.Contact.Phone.TypeEnum {
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

			fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Phone {
				let proto = SignalServiceProtos_DataMessage.Contact.Phone.with { (builder) in
					if let value = self.value {
						builder.value = value
					}

					if let label = self.label {
						builder.label = label
					}

					builder.type = SSKProtoDataMessage_Contact_Phone_TypeUnwrap(self.type)
				}

				return proto
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

			private func SSKProtoDataMessage_Contact_Email_TypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.Email.TypeEnum) -> SSKProtoDataMessage_Contact_Email_Type {
				switch value {
					case .home: return .home
					case .mobile: return .mobile
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_Email_TypeUnwrap(_ value: SSKProtoDataMessage_Contact_Email_Type) -> SignalServiceProtos_DataMessage.Contact.Email.TypeEnum {
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

			fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.Email {
				let proto = SignalServiceProtos_DataMessage.Contact.Email.with { (builder) in
					if let value = self.value {
						builder.value = value
					}

					if let label = self.label {
						builder.label = label
					}

					builder.type = SSKProtoDataMessage_Contact_Email_TypeUnwrap(self.type)
				}

				return proto
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

			private func SSKProtoDataMessage_Contact_PostalAddress_TypeWrap(_ value: SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum) -> SSKProtoDataMessage_Contact_PostalAddress_Type {
				switch value {
					case .home: return .home
					case .work: return .work
					case .custom: return .custom
				}
			}

			private func SSKProtoDataMessage_Contact_PostalAddress_TypeUnwrap(_ value: SSKProtoDataMessage_Contact_PostalAddress_Type) -> SignalServiceProtos_DataMessage.Contact.PostalAddress.TypeEnum {
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

			fileprivate var asProtobuf: SignalServiceProtos_DataMessage.Contact.PostalAddress {
				let proto = SignalServiceProtos_DataMessage.Contact.PostalAddress.with { (builder) in
					builder.type = SSKProtoDataMessage_Contact_PostalAddress_TypeUnwrap(self.type)

					if let street = self.street {
						builder.street = street
					}

					if let label = self.label {
						builder.label = label
					}

					if let neighborhood = self.neighborhood {
						builder.neighborhood = neighborhood
					}

					if let pobox = self.pobox {
						builder.pobox = pobox
					}

					if let region = self.region {
						builder.region = region
					}

					if let city = self.city {
						builder.city = city
					}

					if let country = self.country {
						builder.country = country
					}

					if let postcode = self.postcode {
						builder.postcode = postcode
					}
				}

				return proto
			}
		}

		// MARK: - SSKProtoDataMessage_Contact_Avatar

		@objc public class SSKProtoDataMessage_Contact_Avatar: NSObject {

			@objc public let avatar: SSKProtoAttachmentPointer?
			@objc public let isProfile: Bool

			@objc public init(avatar: SSKProtoAttachmentPointer?, isProfile: Bool) {
				self.avatar = avatar
				self.isProfile = isProfile
			}

			@objc
			public func serializedData() throws -> Data {
			    return try self.asProtobuf.serializedData()
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

				var addressUnwrapped = [SignalServiceProtos_DataMessage.Contact.PostalAddress]()
				for item in address {
					addressUnwrapped.append(item.asProtobuf)
				}
				builder.address = addressUnwrapped

				var emailUnwrapped = [SignalServiceProtos_DataMessage.Contact.Email]()
				for item in email {
					emailUnwrapped.append(item.asProtobuf)
				}
				builder.email = emailUnwrapped

				if let organization = self.organization {
					builder.organization = organization
				}

				if let avatar = self.avatar {
					builder.avatar = avatar.asProtobuf
				}
			}

			return proto
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

	fileprivate var asProtobuf: SignalServiceProtos_DataMessage {
		let proto = SignalServiceProtos_DataMessage.with { (builder) in
			if let body = self.body {
				builder.body = body
			}

			if let group = self.group {
				builder.group = group.asProtobuf
			}

			var attachmentsUnwrapped = [SignalServiceProtos_AttachmentPointer]()
			for item in attachments {
				attachmentsUnwrapped.append(item.asProtobuf)
			}
			builder.attachments = attachmentsUnwrapped

			builder.expireTimer = self.expireTimer

			builder.flags = self.flags

			builder.timestamp = self.timestamp

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}

			var contactUnwrapped = [SignalServiceProtos_DataMessage.Contact]()
			for item in contact {
				contactUnwrapped.append(item.asProtobuf)
			}
			builder.contact = contactUnwrapped

			if let quote = self.quote {
				builder.quote = quote.asProtobuf
			}
		}

		return proto
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

	public enum SSKProtoReceiptMessageError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoReceiptMessage_Type

	@objc public enum SSKProtoReceiptMessage_Type: Int32 {
		case delivery = 0
		case read = 1
	}

	private func SSKProtoReceiptMessage_TypeWrap(_ value: SignalServiceProtos_ReceiptMessage.TypeEnum) -> SSKProtoReceiptMessage_Type {
		switch value {
			case .delivery: return .delivery
			case .read: return .read
		}
	}

	private func SSKProtoReceiptMessage_TypeUnwrap(_ value: SSKProtoReceiptMessage_Type) -> SignalServiceProtos_ReceiptMessage.TypeEnum {
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

	fileprivate var asProtobuf: SignalServiceProtos_ReceiptMessage {
		let proto = SignalServiceProtos_ReceiptMessage.with { (builder) in
			builder.type = SSKProtoReceiptMessage_TypeUnwrap(self.type)

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

	public enum SSKProtoVerifiedError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoVerified_State

	@objc public enum SSKProtoVerified_State: Int32 {
		case `default` = 0
		case verified = 1
		case unverified = 2
	}

	private func SSKProtoVerified_StateWrap(_ value: SignalServiceProtos_Verified.State) -> SSKProtoVerified_State {
		switch value {
			case .default: return .default
			case .verified: return .verified
			case .unverified: return .unverified
		}
	}

	private func SSKProtoVerified_StateUnwrap(_ value: SSKProtoVerified_State) -> SignalServiceProtos_Verified.State {
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

	fileprivate var asProtobuf: SignalServiceProtos_Verified {
		let proto = SignalServiceProtos_Verified.with { (builder) in
			if let destination = self.destination {
				builder.destination = destination
			}

			builder.state = SSKProtoVerified_StateUnwrap(self.state)

			if let identityKey = self.identityKey {
				builder.identityKey = identityKey
			}

			if let nullMessage = self.nullMessage {
				builder.nullMessage = nullMessage
			}
		}

		return proto
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

		fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Sent {
			let proto = SignalServiceProtos_SyncMessage.Sent.with { (builder) in
				if let destination = self.destination {
					builder.destination = destination
				}

				if let message = self.message {
					builder.message = message.asProtobuf
				}

				builder.timestamp = self.timestamp

				builder.expirationStartTimestamp = self.expirationStartTimestamp
			}

			return proto
		}
	}

	// MARK: - SSKProtoSyncMessage_Contacts

	@objc public class SSKProtoSyncMessage_Contacts: NSObject {

		@objc public let blob: SSKProtoAttachmentPointer?
		@objc public let isComplete: Bool

		@objc public init(blob: SSKProtoAttachmentPointer?, isComplete: Bool) {
			self.blob = blob
			self.isComplete = isComplete
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
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

		fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Groups {
			let proto = SignalServiceProtos_SyncMessage.Groups.with { (builder) in
				if let blob = self.blob {
					builder.blob = blob.asProtobuf
				}
			}

			return proto
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

		private func SSKProtoSyncMessage_Request_TypeWrap(_ value: SignalServiceProtos_SyncMessage.Request.TypeEnum) -> SSKProtoSyncMessage_Request_Type {
			switch value {
				case .unknown: return .unknown
				case .contacts: return .contacts
				case .groups: return .groups
				case .blocked: return .blocked
				case .configuration: return .configuration
			}
		}

		private func SSKProtoSyncMessage_Request_TypeUnwrap(_ value: SSKProtoSyncMessage_Request_Type) -> SignalServiceProtos_SyncMessage.Request.TypeEnum {
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

		fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Request {
			let proto = SignalServiceProtos_SyncMessage.Request.with { (builder) in
				builder.type = SSKProtoSyncMessage_Request_TypeUnwrap(self.type)
			}

			return proto
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

	// MARK: - SSKProtoSyncMessage_Configuration

	@objc public class SSKProtoSyncMessage_Configuration: NSObject {

		@objc public let readReceipts: Bool

		@objc public init(readReceipts: Bool) {
			self.readReceipts = readReceipts
		}

		@objc
		public func serializedData() throws -> Data {
		    return try self.asProtobuf.serializedData()
		}

		fileprivate var asProtobuf: SignalServiceProtos_SyncMessage.Configuration {
			let proto = SignalServiceProtos_SyncMessage.Configuration.with { (builder) in
				builder.readReceipts = self.readReceipts
			}

			return proto
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

	fileprivate var asProtobuf: SignalServiceProtos_SyncMessage {
		let proto = SignalServiceProtos_SyncMessage.with { (builder) in
			if let sent = self.sent {
				builder.sent = sent.asProtobuf
			}

			if let groups = self.groups {
				builder.groups = groups.asProtobuf
			}

			if let contacts = self.contacts {
				builder.contacts = contacts.asProtobuf
			}

			var readUnwrapped = [SignalServiceProtos_SyncMessage.Read]()
			for item in read {
				readUnwrapped.append(item.asProtobuf)
			}
			builder.read = readUnwrapped

			if let request = self.request {
				builder.request = request.asProtobuf
			}

			if let verified = self.verified {
				builder.verified = verified.asProtobuf
			}

			if let blocked = self.blocked {
				builder.blocked = blocked.asProtobuf
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

	public enum SSKProtoAttachmentPointerError: Error {
	    case invalidProtobuf(description: String)
	}

	// MARK: - SSKProtoAttachmentPointer_Flags

	@objc public enum SSKProtoAttachmentPointer_Flags: Int32 {
		case voiceMessage = 1
	}

	private func SSKProtoAttachmentPointer_FlagsWrap(_ value: SignalServiceProtos_AttachmentPointer.Flags) -> SSKProtoAttachmentPointer_Flags {
		switch value {
			case .voiceMessage: return .voiceMessage
		}
	}

	private func SSKProtoAttachmentPointer_FlagsUnwrap(_ value: SSKProtoAttachmentPointer_Flags) -> SignalServiceProtos_AttachmentPointer.Flags {
		switch value {
			case .voiceMessage: return .voiceMessage
		}
	}

	@objc public let height: UInt32
	@objc public let id: UInt64
	@objc public let key: Data?
	@objc public let contentType: String?
	@objc public let thumbnail: Data?
	@objc public let size: UInt32
	@objc public let fileName: String?
	@objc public let digest: Data?
	@objc public let width: UInt32
	@objc public let flags: UInt32

	@objc public init(height: UInt32, id: UInt64, key: Data?, contentType: String?, thumbnail: Data?, size: UInt32, fileName: String?, digest: Data?, width: UInt32, flags: UInt32) {
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

	fileprivate var asProtobuf: SignalServiceProtos_AttachmentPointer {
		let proto = SignalServiceProtos_AttachmentPointer.with { (builder) in
			builder.height = self.height

			builder.id = self.id

			if let key = self.key {
				builder.key = key
			}

			if let contentType = self.contentType {
				builder.contentType = contentType
			}

			if let thumbnail = self.thumbnail {
				builder.thumbnail = thumbnail
			}

			builder.size = self.size

			if let fileName = self.fileName {
				builder.fileName = fileName
			}

			if let digest = self.digest {
				builder.digest = digest
			}

			builder.width = self.width

			builder.flags = self.flags
		}

		return proto
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

	private func SSKProtoGroupContext_TypeWrap(_ value: SignalServiceProtos_GroupContext.TypeEnum) -> SSKProtoGroupContext_Type {
		switch value {
			case .unknown: return .unknown
			case .update: return .update
			case .deliver: return .deliver
			case .quit: return .quit
			case .requestInfo: return .requestInfo
		}
	}

	private func SSKProtoGroupContext_TypeUnwrap(_ value: SSKProtoGroupContext_Type) -> SignalServiceProtos_GroupContext.TypeEnum {
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

	fileprivate var asProtobuf: SignalServiceProtos_GroupContext {
		let proto = SignalServiceProtos_GroupContext.with { (builder) in
			if let id = self.id {
				builder.id = id
			}

			if let name = self.name {
				builder.name = name
			}

			builder.type = SSKProtoGroupContext_TypeUnwrap(self.type)

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			var membersUnwrapped = [String]()
			for item in members {
				membersUnwrapped.append(item)
			}
			builder.members = membersUnwrapped
		}

		return proto
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

	@objc public let number: String?
	@objc public let avatar: SSKProtoContactDetails_Avatar?
	@objc public let name: String?
	@objc public let verified: SSKProtoVerified?
	@objc public let color: String?
	@objc public let blocked: Bool
	@objc public let profileKey: Data?
	@objc public let expireTimer: UInt32

	@objc public init(number: String?, avatar: SSKProtoContactDetails_Avatar?, name: String?, verified: SSKProtoVerified?, color: String?, blocked: Bool, profileKey: Data?, expireTimer: UInt32) {
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

	fileprivate var asProtobuf: SignalServiceProtos_ContactDetails {
		let proto = SignalServiceProtos_ContactDetails.with { (builder) in
			if let number = self.number {
				builder.number = number
			}

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			if let name = self.name {
				builder.name = name
			}

			if let verified = self.verified {
				builder.verified = verified.asProtobuf
			}

			if let color = self.color {
				builder.color = color
			}

			builder.blocked = self.blocked

			if let profileKey = self.profileKey {
				builder.profileKey = profileKey
			}

			builder.expireTimer = self.expireTimer
		}

		return proto
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

	@objc public let id: Data?
	@objc public let members: [String]
	@objc public let name: String?
	@objc public let active: Bool
	@objc public let avatar: SSKProtoGroupDetails_Avatar?
	@objc public let color: String?
	@objc public let expireTimer: UInt32

	@objc public init(id: Data?, members: [String], name: String?, active: Bool, avatar: SSKProtoGroupDetails_Avatar?, color: String?, expireTimer: UInt32) {
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

	fileprivate var asProtobuf: SignalServiceProtos_GroupDetails {
		let proto = SignalServiceProtos_GroupDetails.with { (builder) in
			if let id = self.id {
				builder.id = id
			}

			var membersUnwrapped = [String]()
			for item in members {
				membersUnwrapped.append(item)
			}
			builder.members = membersUnwrapped

			if let name = self.name {
				builder.name = name
			}

			builder.active = self.active

			if let avatar = self.avatar {
				builder.avatar = avatar.asProtobuf
			}

			if let color = self.color {
				builder.color = color
			}

			builder.expireTimer = self.expireTimer
		}

		return proto
	}
}
