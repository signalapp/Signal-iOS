//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

#if DEBUG

@objc
public class OWSFakeUDManager: NSObject, OWSUDManager {

    private var udRecipientSet = Set<String>()

    // MARK: -

    @objc
    public func isUDRecipientId(_ recipientId: String) -> Bool {
        return udRecipientSet.contains(recipientId)
    }

    @objc
    public func addUDRecipientId(_ recipientId: String) {
        udRecipientSet.insert(recipientId)
    }

    @objc
    public func removeUDRecipientId(_ recipientId: String) {
        udRecipientSet.remove(recipientId)
    }
}

#endif
