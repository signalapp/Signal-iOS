//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class OWSMessagesBubbleImageFactory: NSObject {

    @objc
    public static let shared = OWSMessagesBubbleImageFactory()

    // TODO: UIView is a little bit expensive to instantiate.
    //       Can we cache this value?
    private lazy var isRTL: Bool = {
        return UIView().isRTL()
    }()

    @objc
    public static let bubbleColorIncoming = UIColor.ows_messageBubbleLightGray

    @objc
    public static let bubbleColorOutgoingUnsent = UIColor.gray

    @objc
    public static let bubbleColorOutgoingSending = UIColor.ows_fadedBlue

    @objc
    public static let bubbleColorOutgoingSent = UIColor.ows_materialBlue

    @objc
    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return OWSMessagesBubbleImageFactory.bubbleColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingUnsent
            case .sending:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingSending
            default:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
        }
    }
}
