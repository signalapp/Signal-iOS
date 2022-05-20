// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

/// This custom UITableView allows us to lock the contentOffset to a specific value - it's current used to prevent
/// the ConversationVC first responder resignation from making the MediaGalleryDetailViewController transition
/// from looking buggy (ie. the table scrolls down with the resignation during the transition)
public class InsetLockableTableView: UITableView {
    public var lockContentOffset: Bool = false {
        didSet {
            guard !lockContentOffset else { return }
            
            self.contentOffset = newOffset
        }
    }
    public var oldOffset: CGPoint = .zero
    public var newOffset: CGPoint = .zero
    
    public override func layoutSubviews() {
        newOffset = self.contentOffset
        
        guard !lockContentOffset else {
            self.contentOffset = CGPoint(
                x: newOffset.x,
                y: oldOffset.y
            )
            super.layoutSubviews()
            return
        }
        
        super.layoutSubviews()
        
        oldOffset = self.contentOffset
    }
}
