//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

public class HVCellAccessibilityCustomAction: UIAccessibilityCustomAction {

    var type: HVCellAccessibilityCustomActionType
    var threadViewModel: ThreadViewModel

    init(name: String, type: HVCellAccessibilityCustomActionType, threadViewModel: ThreadViewModel, target: Any?, selector: Selector) {
        self.type = type
        self.threadViewModel = threadViewModel
        super.init(name: name, target: target, selector: selector)
    }
}

// MARK: -

public enum HVCellAccessibilityCustomActionType: Int {
    case delete
    case archive
    case markRead
    case markUnread
    case pin
    case unpin
}
