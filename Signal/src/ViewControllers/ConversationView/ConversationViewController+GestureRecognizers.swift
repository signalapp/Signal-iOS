//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol ConversationViewLongPressableCell {
    var viewItem: ConversationViewItem? { get }
    func handleLongPressGesture(_ sender: UILongPressGestureRecognizer)
}

@objc
protocol ConversationViewPannableCell {
    var viewItem: ConversationViewItem? { get }
    func handlePanGesture(_ sender: UIPanGestureRecognizer)
}

extension ConversationViewController: UIGestureRecognizerDelegate {
    @objc
    func createGestureRecognizers() {
        longPressGestureRecognizer.addTarget(self, action: #selector(handleLongPressGesture))
        longPressGestureRecognizer.delegate = self
        collectionView.addGestureRecognizer(longPressGestureRecognizer)

        panGestureRecognizer.addTarget(self, action: #selector(handlePanGesture))
        panGestureRecognizer.delegate = self
        collectionView.addGestureRecognizer(panGestureRecognizer)

        // Allow panning with trackpad
        if #available(iOS 13.4, *) { panGestureRecognizer.allowedScrollTypesMask = .continuous }

        // There are cases where we don't have a navigation controller, such as if we got here through 3d touch.
        // Make sure we only register the gesture interaction if it actually exists. This helps the swipe back
        // gesture work reliably without conflict with audio scrubbing or swipe-to-repy.
        if let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer {
            panGestureRecognizer.require(toFail: interactivePopGestureRecognizer)
        }
    }

    private func cellAtPoint<T>(_ point: CGPoint) -> T? {
        guard let indexPath = collectionView.indexPathForItem(at: point),
            let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        return cell as? T
    }

    private func cellForInteractionId<T>(_ interactionId: String) -> T? {
        guard let indexPath = conversationViewModel.indexPath(forInteractionId: interactionId),
            let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        return cell as? T
    }

    @objc
    func handleLongPressGesture(_ sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            let touch = sender.location(in: collectionView)
            guard let cell: ConversationViewLongPressableCell = cellAtPoint(touch) else { return }
            cell.handleLongPressGesture(sender)
            longPressGestureCurrentInteractionId = cell.viewItem?.interaction.uniqueId
        } else if let longPressGestureCurrentInteractionId = longPressGestureCurrentInteractionId,
            let cell: ConversationViewLongPressableCell = cellForInteractionId(longPressGestureCurrentInteractionId) {
            cell.handleLongPressGesture(sender)
        } else {
            // cancel any existing gesture, we no longer know what cell it belongs to.
            longPressGestureCurrentInteractionId = nil
            longPressGestureRecognizer.isEnabled = false
            longPressGestureRecognizer.isEnabled = true
        }

        if [.ended, .cancelled, .failed].contains(sender.state) {
            longPressGestureCurrentInteractionId = nil
        }
    }

    @objc
    func handlePanGesture(_ sender: UIPanGestureRecognizer) {
        if sender.state == .began {
            let touch = sender.location(in: collectionView)
            guard let cell: ConversationViewPannableCell = cellAtPoint(touch) else { return }
            cell.handlePanGesture(sender)
            panGestureCurrentInteractionId = cell.viewItem?.interaction.uniqueId
        } else if let panGestureCurrentInteractionId = panGestureCurrentInteractionId,
            let cell: ConversationViewPannableCell = cellForInteractionId(panGestureCurrentInteractionId) {
            cell.handlePanGesture(sender)
        } else {
            // cancel any existing gesture, we no longer know what cell it belongs to.
            panGestureCurrentInteractionId = nil
            panGestureRecognizer.isEnabled = false
            panGestureRecognizer.isEnabled = true
        }

        if [.ended, .cancelled, .failed].contains(sender.state) {
            panGestureCurrentInteractionId = nil
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !isShowingSelectionUI else { return false }

        if gestureRecognizer == panGestureRecognizer {
            // Only allow the pan gesture to recognize horizontal panning,
            // to avoid conflicts with the conversation view scroll view.
            let translation = panGestureRecognizer.translation(in: view)
            return abs(translation.x) > abs(translation.y)
        } else {
            return true
        }
    }
}
