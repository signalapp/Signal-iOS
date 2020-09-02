//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objcMembers class OWSCellAccessibilityCustomAction: UIAccessibilityCustomAction {

    var type: OWSCellAccessibilityCustomActionType
    var thread: TSThread

    init(name: String, type: OWSCellAccessibilityCustomActionType, thread: TSThread, target: Any?, selector: Selector) {
        self.type = type
        self.thread = thread
        super.init(name: name, target: target, selector: selector)
    }
}

@objc enum OWSCellAccessibilityCustomActionType: Int {
    case delete
    case archive
    case markRead
    case markUnread
    case pin
    case unpin
}
