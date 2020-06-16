
@objc(LKTTLUtilities)
public final class TTLUtilities : NSObject {

    /// If a message type specifies an invalid TTL, this will be used.
    public static let fallbackMessageTTL: UInt64 = 4 * 24 * 60 * 60 * 1000

    @objc(LKMessageType)
    public enum MessageType : Int {
        case address
        case call
        case disappearingMessagesConfiguration
        case ephemeral
        case friendRequest
        case linkDevice
        case profileKey
        case receipt
        case regular
        case sessionRequest
        case sync
        case typingIndicator
        case unlinkDevice
    }

    @objc public static func getTTL(for messageType: MessageType) -> UInt64 {
        switch messageType {
        case .address: return 1 * kMinuteInMs
        case .call: return 1 * kMinuteInMs
        case .disappearingMessagesConfiguration: return 4 * kDayInMs - 1 * kHourInMs
        case .ephemeral: return 4 * kDayInMs - 1 * kHourInMs
        case .friendRequest: return 4 * kDayInMs
        case .linkDevice: return 4 * kMinuteInMs
        case .profileKey: return 4 * kDayInMs - 1 * kHourInMs
        case .receipt: return 4 * kDayInMs - 1 * kHourInMs
        case .regular: return 2 * kDayInMs
        case .sessionRequest: return 4 * kDayInMs - 1 * kHourInMs
        case .sync: return 4 * kDayInMs - 1 * kHourInMs
        case .typingIndicator: return 1 * kMinuteInMs
        case .unlinkDevice: return 4 * kDayInMs - 1 * kHourInMs
        }
    }
}
