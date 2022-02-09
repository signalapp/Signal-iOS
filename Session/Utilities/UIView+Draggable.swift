// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

extension UIView {
    
    func makeViewDraggable() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGestureRecognizer)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self.superview!)
        if let draggedView = gesture.view {
            draggedView.center = location
            if gesture.state == .ended {
                if draggedView.frame.midX >= self.superview!.layer.frame.width / 2 {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = self.superview!.layer.frame.width - draggedView.width() / 2
                    }, completion: nil)
                }else{
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = draggedView.width() / 2
                    }, completion: nil)
                }
                let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
                if draggedView.frame.minY <= topMargin {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = topMargin + draggedView.height() / 2
                    }, completion: nil)
                }
                let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom
                if draggedView.frame.maxY >= self.superview!.layer.frame.height {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = self.layer.frame.height - draggedView.height() / 2 - bottomMargin
                    }, completion: nil)
                }
            }
        }
    }
    
}
