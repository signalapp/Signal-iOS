//
//  SlugViewLayout.swift
//  Forsta
//
//  Created by Mark Descalzo on 5/22/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit
import CoreGraphics

protocol SlugLayoutDelegate: class {
    func rowHeight() -> CGFloat
    func widthForSlug(at indexPath: IndexPath) -> CGFloat
}

class SlugViewLayout: UICollectionViewLayout {
    
    weak var delegate: SlugLayoutDelegate!
    
    private let cellPadding: CGFloat = 3.0
    private var lines: CGFloat = 0
    private var attrCache = [UICollectionViewLayoutAttributes]()
    private let insets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
    
    override var collectionViewContentSize: CGSize {
        get {
            guard collectionView != nil, attrCache.count > 0 else {
                return CGSize()
            }
            let width: CGFloat = ((self.collectionView?.frame.size.width)! - (insets.left + insets.right))
            let totalPadding = (lines > 1.0 as CGFloat ? (cellPadding * (lines - 1.0)) : 0.0)
            let height: CGFloat = (lines * (delegate?.rowHeight())!) + (insets.top + insets.bottom) + totalPadding

            return CGSize(width: width, height: height)
        }
    }
    
    override func prepare() {
        
        guard let collectionView = collectionView else {
            return
        }
        
        // Reset the things
        attrCache.removeAll()
        lines = 0.0
        let boundaryX = collectionView.contentSize.width

        for item in 0 ..< collectionView.numberOfItems(inSection: 0) {
            
            let indexPath = IndexPath(item: item, section: 0)
            var frame = CGRect()
            
            let width = delegate.widthForSlug(at: indexPath) + delegate.rowHeight()
            if indexPath.item == 0 {
                frame = CGRect(x: insets.left, y: insets.top, width: width, height: delegate.rowHeight())
                lines = 1
            } else {
                let previousAttributes = attrCache[item-1]
                

                var newX = previousAttributes.frame.origin.x + previousAttributes.frame.size.width + cellPadding
                var newY = previousAttributes.frame.origin.y
                
                if  (newX + width - insets.right) > boundaryX {
                    newX = insets.left
                    newY = newY + delegate.rowHeight() + cellPadding
                    lines += 1
                }
                frame = CGRect(x: newX, y: newY, width: self.delegate.widthForSlug(at: indexPath) + self.delegate.rowHeight(), height: self.delegate.rowHeight())
            }
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame
            attrCache.append(attributes)
        }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return attrCache[indexPath.item]
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var visibleLayoutAttributes = [UICollectionViewLayoutAttributes]()
        
        // Loop through the cache and look for items in the rect
        for attributes in attrCache {
            if attributes.frame.intersects(rect) {
                visibleLayoutAttributes.append(attributes)
            }
        }
        return visibleLayoutAttributes
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
    }
    
    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
    }
}
