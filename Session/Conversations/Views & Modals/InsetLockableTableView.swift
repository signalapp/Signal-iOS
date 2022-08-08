// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

/// This custom UITableView gives us two convenience behaviours:
///
/// 1. It allows us to lock the contentOffset to a specific value - it's currently used to prevent the ConversationVC first
/// responder resignation from making the MediaGalleryDetailViewController transition from looking buggy (ie. the table
/// scrolls down with the resignation during the transition)
///
/// 2. It allows us to provode a callback which gets triggered if a condition closure returns true - it's currently used to prevent
/// the table view from jumping when inserting new pages at the top of a conversation screen
public class InsetLockableTableView: UITableView {
    public var lockContentOffset: Bool = false {
        didSet {
            guard !lockContentOffset else { return }
            
            self.contentOffset = newOffset
        }
    }
    public var oldOffset: CGPoint = .zero
    public var newOffset: CGPoint = .zero
    private var callbackCondition: ((Int, [Int], CGSize) -> Bool)?
    private var afterLayoutSubviewsCallback: (() -> ())?
    
    public override func layoutSubviews() {
        self.newOffset = self.contentOffset
        
        // Store the callback locally to prevent infinite loops
        var callback: (() -> ())?
        
        if self.checkCallbackCondition() {
            callback = self.afterLayoutSubviewsCallback
            self.afterLayoutSubviewsCallback = nil
        }
        
        guard !lockContentOffset else {
            self.contentOffset = CGPoint(
                x: newOffset.x,
                y: oldOffset.y
            )
            
            super.layoutSubviews()
            callback?()
            return
        }
        
        super.layoutSubviews()
        callback?()
        
        self.oldOffset = self.contentOffset
    }
    
    // MARK: - Functions
    
    public func afterNextLayoutSubviews(
        when condition: @escaping (Int, [Int], CGSize) -> Bool,
        then callback: @escaping () -> ()
    ) {
        self.callbackCondition = condition
        self.afterLayoutSubviewsCallback = callback
    }
    
    private func checkCallbackCondition() -> Bool {
        guard self.callbackCondition != nil else { return false }
        
        let numSections: Int = self.numberOfSections
        let numRowInSections: [Int] = (0..<numSections)
            .map { self.numberOfRows(inSection: $0) }
        
        // Store the layout info locally so if they pass we can clear the states before running to
        // prevent layouts within the callbacks from triggering infinite loops
        guard self.callbackCondition?(numSections, numRowInSections, self.contentSize) == true else {
            return false
        }
        
        self.callbackCondition = nil
        return true
    }
}
