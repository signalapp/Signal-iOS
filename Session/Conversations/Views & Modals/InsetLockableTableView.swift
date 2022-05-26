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
    private var afterNextLayoutCondition: ((Int, [Int]) -> Bool)?
    private var afterNextLayoutCallback: (() -> ())?
    
    public override func layoutSubviews() {
        newOffset = self.contentOffset
        
        guard !lockContentOffset else {
            self.contentOffset = CGPoint(
                x: newOffset.x,
                y: oldOffset.y
            )
            
            super.layoutSubviews()
            
            self.performNextLayoutCallbackIfPossible()
            return
        }
        
        super.layoutSubviews()
        
        self.performNextLayoutCallbackIfPossible()
        self.oldOffset = self.contentOffset
    }
    
    // MARK: - Function
    
    public func afterNextLayout(when condition: @escaping (Int, [Int]) -> Bool, then callback: @escaping () -> ()) {
        self.afterNextLayoutCondition = condition
        self.afterNextLayoutCallback = callback
    }
    
    private func performNextLayoutCallbackIfPossible() {
        let numSections: Int = self.numberOfSections
        let numRowInSections: [Int] = (0..<numSections)
            .map { self.numberOfRows(inSection: $0) }
        
        guard self.afterNextLayoutCondition?(numSections, numRowInSections) == true else { return }
        
        self.afterNextLayoutCallback?()
        self.afterNextLayoutCondition = nil
        self.afterNextLayoutCallback = nil
    }
}
