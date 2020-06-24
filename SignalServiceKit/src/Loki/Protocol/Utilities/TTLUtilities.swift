
@objc(LKTTLUtilities)
public final class TTLUtilities : NSObject {

    /// If a message type specifies an invalid TTL, this will be used.
    public static let fallbackMessageTTL: UInt64 = 2 * kDayInMs

    @objc(LKMessageType)
    public enum MessageType : Int {
        // Unimportant control messages
        case call, typingIndicator
        // Somewhat important control messages
        case linkDevice
        // Important control messages
        case closedGroupUpdate, disappearingMessagesConfiguration, ephemeral, profileKey, receipt, sessionRequest, sync, unlinkDevice
        // Visible messages
        case friendRequest, regular
    }

    @objc public static func getTTL(for messageType: MessageType) -> UInt64 {
        switch messageType {
        // Unimportant control messages
        case .call, .typingIndicator: return 1 * kMinuteInMs
        // Somewhat important control messages
        case .linkDevice: return 1 * kHourInMs
        // Important control messages
        case .closedGroupUpdate, .disappearingMessagesConfiguration, .ephemeral, .profileKey, .receipt, .sessionRequest, .sync, .unlinkDevice: return 2 * kDayInMs - 1 * kHourInMs
        // Visible messages
        case .friendRequest, .regular: return 2 * kDayInMs
        }
    }
}
