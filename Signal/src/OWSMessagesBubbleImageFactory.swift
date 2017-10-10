//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSMessagesBubbleImageFactory: NSObject {

    let jsqFactory = JSQMessagesBubbleImageFactory()!

    // TODO: UIView is a little bit expensive to instantiate.
    //       Can we cache this value?
    var isRTL: Bool {
        return UIView().isRTL()
    }

    var incoming: JSQMessagesBubbleImage {
        let color = UIColor.jsq_messageBubbleLightGray()!
        return incoming(color: color)
    }

    var outgoing: JSQMessagesBubbleImage {
        let color = UIColor.ows_materialBlue()
        return outgoing(color: color)
    }

    var currentlyOutgoing: JSQMessagesBubbleImage {
        let color = UIColor.ows_fadedBlue()
        return outgoing(color: color)
    }

    var outgoingFailed: JSQMessagesBubbleImage {
        let color = UIColor.gray
        return outgoing(color: color)
    }

    func outgoing(color: UIColor) -> JSQMessagesBubbleImage {
        if isRTL {
            return jsqFactory.incomingMessagesBubbleImage(with: color)
        } else {
            return jsqFactory.outgoingMessagesBubbleImage(with: color)
        }
    }

    func incoming(color: UIColor) -> JSQMessagesBubbleImage {
        if isRTL {
            return jsqFactory.outgoingMessagesBubbleImage(with: color)
        } else {
            return jsqFactory.incomingMessagesBubbleImage(with: color)
        }
    }
}
