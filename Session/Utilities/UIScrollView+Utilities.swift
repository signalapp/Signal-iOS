// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UIScrollView {
    static let fastEndScrollingThen: ((UIScrollView, CGPoint?, @escaping () -> ()) -> ()) = { scrollView, currentTargetOffset, callback in
        let endOffset: CGPoint
        
        if let currentTargetOffset: CGPoint = currentTargetOffset {
            endOffset = currentTargetOffset
        }
        else {
            let currentVelocity: CGPoint = scrollView.panGestureRecognizer.velocity(in: scrollView)
            
            endOffset = CGPoint(
                x: scrollView.contentOffset.x,
                y: scrollView.contentOffset.y - (currentVelocity.y / 100)
            )
        }
        
        guard endOffset != scrollView.contentOffset else {
            return callback()
        }
        
        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                scrollView.setContentOffset(endOffset, animated: false)
            },
            completion: { _ in
                callback()
            }
        )
    }
}
