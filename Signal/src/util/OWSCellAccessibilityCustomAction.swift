//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

import UIKit

@objcMembers class OWSCellAccessibilityCustomAction: UIAccessibilityCustomAction {
    
    var type: OWSCellAccessibilityCustomActionType
    var indexPath: IndexPath
    
    init(name: String, type: OWSCellAccessibilityCustomActionType, indexPath: IndexPath, target: Any?, selector: Selector){
        self.type = type
        self.indexPath = indexPath
        super.init(name: name, target: target, selector: selector)
    }
}

@objc enum OWSCellAccessibilityCustomActionType: Int {
    case delete
    case archive
    case markRead
    case markUnread
}
