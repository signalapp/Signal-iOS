// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public extension Notification.Name {
    static let windowSubviewsChanged = Notification.Name("windowSubviewsChanged")
}


public class TraitObservingWindow: UIWindow {
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        ThemeManager.traitCollectionDidChange(previousTraitCollection)
    }
    
    public override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        
        NotificationCenter.default.post(name: .windowSubviewsChanged, object: nil)
    }
    
    public override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        
        NotificationCenter.default.post(name: .windowSubviewsChanged, object: nil)
    }
}
