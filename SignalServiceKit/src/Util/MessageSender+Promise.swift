//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension MessageSender {

    /**
     * Wrap message sending in a Promise for easier callback chaining.
     */
    func sendMessage(_ namespace: PMKNamespacer, _ message: OutgoingMessagePreparer) -> Promise<Void> {
        return Promise { resolver in
            self.sendMessage(message, success: { resolver.fulfill(()) }, failure: resolver.reject)
        }
    }

    /**
     * Wrap message sending in a Promise for easier callback chaining.
     */
    func sendTemporaryAttachment(_ namespace: PMKNamespacer,
                                 dataSource: DataSource,
                                 contentType: String,
                                 message: TSOutgoingMessage) -> Promise<Void> {
        return Promise { resolver in
            self.sendTemporaryAttachment(dataSource, contentType: contentType, in: message, success: { resolver.fulfill(()) }, failure: resolver.reject)
        }
    }
}
