
@objc(LKSignalMessage)
public final class SignalMessage : NSObject {
    @objc public let type: SSKProtoEnvelope.SSKProtoEnvelopeType
    @objc public let timestamp: UInt64
    @objc public let senderID: String
    @objc public let senderDeviceID: UInt32
    @objc public let content: String
    @objc public let recipientID: String
    @objc(ttl)
    public let objc_ttl: UInt64
    @objc public let isPing: Bool
    
    public var ttl: UInt64? { return objc_ttl != 0 ? objc_ttl : nil }
    
    @objc public init(type: SSKProtoEnvelope.SSKProtoEnvelopeType, timestamp: UInt64, senderID: String, senderDeviceID: UInt32,
        content: String, recipientID: String, ttl: UInt64, isPing: Bool) {
        self.type = type
        self.timestamp = timestamp
        self.senderID = senderID
        self.senderDeviceID = senderDeviceID
        self.content = content
        self.recipientID = recipientID
        self.objc_ttl = ttl
        self.isPing = isPing
        super.init()
    }
}
