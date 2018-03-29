//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import JSQMessagesViewController
import SignalServiceKit

@objc
public class OWSMessagesBubbleImageFactory: NSObject {

    static let shared = OWSMessagesBubbleImageFactory()

    private let jsqFactory = JSQMessagesBubbleImageFactory()!

    // TODO: UIView is a little bit expensive to instantiate.
    //       Can we cache this value?
    private lazy var isRTL: Bool = {
        return UIView().isRTL()
    }()

    public lazy var incoming: JSQMessagesBubbleImage = {
        let color = UIColor.jsq_messageBubbleLightGray()!
        return self.incoming(color: color)
    }()

    public lazy var outgoing: JSQMessagesBubbleImage = {
        let color = UIColor.ows_materialBlue
        return self.outgoing(color: color)
    }()

    public lazy var currentlyOutgoing: JSQMessagesBubbleImage = {
        let color = UIColor.ows_fadedBlue
        return self.outgoing(color: color)
    }()

    public lazy var outgoingFailed: JSQMessagesBubbleImage = {
        let color = UIColor.gray
        return self.outgoing(color: color)
    }()

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

    public static let bubbleColorIncoming = UIColor.jsq_messageBubbleLightGray()!

    public static let bubbleColorOutgoingUnsent = UIColor.gray

    public static let bubbleColorOutgoingSending = UIColor.ows_fadedBlue

    public static let bubbleColorOutgoingSent = UIColor.ows_materialBlue

    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return OWSMessagesBubbleImageFactory.bubbleColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .unsent:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingUnsent
            case .attemptingOut:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingSending
            default:
                return OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
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
