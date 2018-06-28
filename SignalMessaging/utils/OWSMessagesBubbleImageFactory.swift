//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

// TODO: Possibly pull this into Conversation Style.
@objc
public class OWSMessagesBubbleColors: NSObject {

    override private init() {
        super.init()
    }

    @objc
    public static let shared = OWSMessagesBubbleColors()

    // TODO: Remove this!  Incoming bubble colors are now dynamic.
    @objc
    public static let bubbleColorIncoming = UIColor.ows_messageBubbleLightGray

    // TODO:
    @objc
    public static let bubbleColorOutgoingUnsent = UIColor.ows_red

    // TODO:
    @objc
    public static let bubbleColorOutgoingSending = UIColor.ows_light35

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

    @objc
    public static func bubbleTextColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return UIColor.ows_white
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return UIColor.ows_black
            case .sending:
                return UIColor.ows_black
            default:
                return UIColor.ows_black
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
        }
    }
}
