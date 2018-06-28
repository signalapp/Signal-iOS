//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWSMessagesBubbleColors: NSObject {

    override private init() {
        super.init()
    }

    @objc
    public static let shared = OWSMessagesBubbleColors()

    @objc
    public static let bubbleColorIncoming = UIColor.ows_messageBubbleLightGray

    @objc
    public static let bubbleColorOutgoingUnsent = UIColor.gray

    @objc
    public static let bubbleColorOutgoingSending = UIColor.ows_fadedBlue

    @objc
    public static let bubbleColorOutgoingSent = UIColor.ows_light10

    @objc
    public static func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return OWSMessagesBubbleColors.bubbleColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return OWSMessagesBubbleColors.bubbleColorOutgoingUnsent
            case .sending:
                return OWSMessagesBubbleColors.bubbleColorOutgoingSending
            default:
                return OWSMessagesBubbleColors.bubbleColorOutgoingSent
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
        }
    }
}
