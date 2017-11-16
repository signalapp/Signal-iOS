//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSMessagesBubbleImageFactory: NSObject {

    private let jsqFactory = JSQMessagesBubbleImageFactory()!

    // TODO: UIView is a little bit expensive to instantiate.
    //       Can we cache this value?
    private var isRTL: Bool {
        return UIView().isRTL()
    }

    public var incoming: JSQMessagesBubbleImage {
        let color = UIColor.jsq_messageBubbleLightGray()!
        return incoming(color: color)
    }

    public var outgoing: JSQMessagesBubbleImage {
        let color = UIColor.ows_materialBlue()
        return outgoing(color: color)
    }

    public var currentlyOutgoing: JSQMessagesBubbleImage {
        let color = UIColor.ows_fadedBlue()
        return outgoing(color: color)
    }

    public var outgoingFailed: JSQMessagesBubbleImage {
        let color = UIColor.gray
        return outgoing(color: color)
    }

    public func bubble(message: TSMessage) -> JSQMessagesBubbleImage {
        if message is TSIncomingMessage {
            return self.incoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .unsent:
                return outgoingFailed
            case .attemptingOut:
                return currentlyOutgoing
            default:
                return outgoing
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return outgoing
        }
    }

    private func outgoing(color: UIColor) -> JSQMessagesBubbleImage {
        if isRTL {
            return jsqFactory.incomingMessagesBubbleImage(with: color)
        } else {
            return jsqFactory.outgoingMessagesBubbleImage(with: color)
        }
    }

    private func incoming(color: UIColor) -> JSQMessagesBubbleImage {
        if isRTL {
            return jsqFactory.outgoingMessagesBubbleImage(with: color)
        } else {
            return jsqFactory.incomingMessagesBubbleImage(with: color)
        }
    }
}
