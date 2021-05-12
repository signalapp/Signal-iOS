//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

@objcMembers class OWSCellAccessibilityCustomAction: UIAccessibilityCustomAction {

    var type: OWSCellAccessibilityCustomActionType
    var threadViewModel: ThreadViewModel

    init(name: String, type: OWSCellAccessibilityCustomActionType, threadViewModel: ThreadViewModel, target: Any?, selector: Selector) {
        self.type = type
        self.threadViewModel = threadViewModel
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
