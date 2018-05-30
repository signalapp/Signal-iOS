//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import JSQMessagesViewController
import SignalServiceKit

@objc
public class OWSMessagesBubbleImageFactory: NSObject {

    @objc
    public static let shared = OWSMessagesBubbleImageFactory()

    private let jsqFactory = JSQMessagesBubbleImageFactory()!

    // TODO: UIView is a little bit expensive to instantiate.
    //       Can we cache this value?
    private lazy var isRTL: Bool = {
        return UIView().isRTL()
    }()

    @objc
    public lazy var incoming: JSQMessagesBubbleImage = {
        let color = OWSMessagesBubbleImageFactory.bubbleColorIncoming
        return self.incoming(color: color)
    }()

    @objc
    public lazy var outgoing: JSQMessagesBubbleImage = {
        let color = OWSMessagesBubbleImageFactory.bubbleColorOutgoingSent
        return self.outgoing(color: color)
    }()

    @objc
    public lazy var currentlyOutgoing: JSQMessagesBubbleImage = {
        let color = OWSMessagesBubbleImageFactory.bubbleColorOutgoingSending
        return self.outgoing(color: color)
    }()

    @objc
    public lazy var outgoingFailed: JSQMessagesBubbleImage = {
        let color = OWSMessagesBubbleImageFactory.bubbleColorOutgoingUnsent
        return self.outgoing(color: color)
    }()

    @objc
    public func bubble(message: TSMessage) -> JSQMessagesBubbleImage {
        if message is TSIncomingMessage {
            return self.incoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return outgoingFailed
            case .sending:
                return currentlyOutgoing
            default:
                return outgoing
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return outgoing
        }
    }

    @objc
    public static let bubbleColorIncoming = UIColor.jsq_messageBubbleLightGray()!

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
