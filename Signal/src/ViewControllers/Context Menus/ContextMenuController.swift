//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuControllerDelegate: AnyObject {
    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController)
}

private protocol ContextMenuViewDelegate: AnyObject {
    func contextMenuViewPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect
    func contextMenuViewAuxPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect
    func contextMenuViewAnimationState(_ contextMenuView: ContextMenuHostView) -> ContextMenuAnimationState
    func contextMenuViewPreviewFrameForAccessoryLayout(_ contextMenuView: ContextMenuHostView) -> CGRect
}

private enum ContextMenuAnimationState {
    case none
    case animateIn
    case animateOut
}

private class ContextMenuHostView: UIView {

    weak var delegate: ContextMenuViewDelegate?
    var previewViewAlignment: ContextMenuTargetedPreview.Alignment = .center

    private var contentAreaInsets: UIEdgeInsets {
        let minPadding: CGFloat = 8
        return UIEdgeInsets(top: max(safeAreaInsets.top, minPadding),
                     leading: max(safeAreaInsets.leading, minPadding),
                     bottom: max(safeAreaInsets.bottom, minPadding),
                     trailing: max(safeAreaInsets.trailing, minPadding))
    }

    var blurView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = blurView {
                addSubview(view)
            }
        }
    }

    var previewView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = previewView {
                addSubview(view)

                if DebugFlags.showContextMenuDebugRects {
                    view.addBorder(with: UIColor.blue)
                }
            }
        }
    }

    var auxiliaryPreviewView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = auxiliaryPreviewView {
                addSubview(view)

                if DebugFlags.showContextMenuDebugRects {
                    view.addBorder(with: UIColor.blue)
                }
            }
        }
    }

    var accessoryViews: [ContextMenuTargetedPreviewAccessory]? {
        didSet {
            if let oldAccessoryViews = oldValue {
                for oldAccessory in oldAccessoryViews {
                    oldAccessory.accessoryView.removeFromSuperview()
                }
            }

            if let newAccessoryViews = accessoryViews {
                for accessory in newAccessoryViews {
                    addSubview(accessory.accessoryView)

                    if DebugFlags.showContextMenuDebugRects {
                        accessory.accessoryView.addRedBorder()
                    }
                }
            }
        }
    }

    var dismissButton: UIButton? {
        didSet {
            oldValue?.removeFromSuperview()
            if let dismissButton = dismissButton {
                addSubview(dismissButton)

                if DebugFlags.showContextMenuDebugRects {
                    dismissButton.addBorder(with: UIColor.blue)
                }
            }
        }
    }

    lazy var previewSourceFrame: CGRect = delegate?.contextMenuViewPreviewSourceFrame(self) ?? CGRect.zero
    lazy var auxPreviewSourceFrame: CGRect = delegate?.contextMenuViewAuxPreviewSourceFrame(self) ?? CGRect.zero

    private let minPreviewScaleFactor: CGFloat = 0.1

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView?.frame = bounds
        dismissButton?.frame = bounds

        let animationState = delegate?.contextMenuViewAnimationState(self) ?? .none
        var auxVerticalOffset: CGFloat = 0
        if let previewView = self.previewView {
            // Let the controller manage the preview's frame if animating
            if animationState != .animateOut {
                previewView.frame = targetPreviewFrame()
            }

            if let auxView = auxiliaryPreviewView {
                auxView.sizeToFit()
                auxView.frame = targetAuxiliaryPreviewFrame(previewFrame: previewView.frame)
                auxVerticalOffset = max(auxView.frame.maxY - previewView.frame.maxY, 0)
            }
        }

        if let accessories = accessoryViews {
            var accessoryFrames: [CGRect] = []
            for accessory in accessories {

                let animationState = delegate?.contextMenuViewAnimationState(self) ?? .none
                guard !(accessory.animateAccessoryPresentationAlongsidePreview && animationState == .animateOut) else {
                    if let targetFrame = accessory.targetAnimateOutFrame, accessory.accessoryView.frame.size == CGSize.zero {
                        accessory.accessoryView.frame = targetFrame
                    }
                    continue
                }

                layoutAccessoryView(accessory, auxVerticalOffset: auxVerticalOffset)

                var frame = accessory.accessoryView.frame

                // Check for accessory view intersects
                for accessoryFrame in accessoryFrames {
                    if accessoryFrame != frame && frame.intersects(accessoryFrame) {
                        // We have an intersect! Only handling vertical intersects for now
                        if frame.y < accessoryFrame.maxY {
                            frame.y += accessoryFrame.maxY - frame.y + 12
                        }

                        // Shrink accessory view if needed
                        let contentBounds = bounds.inset(by: contentAreaInsets)
                        if frame.maxY > contentBounds.maxY {
                            frame.size.height -= frame.maxY - contentBounds.maxY
                        }

                        accessory.accessoryView.frame = frame
                        break
                    }
                }

                accessoryFrames.append(frame)
            }
        }

    }

    private func targetPreviewFrame() -> CGRect {
        var previewFrame = previewSourceFrame
        let auxPreviewFrame = auxPreviewSourceFrame
        let auxVerticalOffset = max(auxPreviewFrame.maxY - previewSourceFrame.maxY, 0)
        let contentRect = bounds.inset(by: contentAreaInsets)

        // Check for Y-offset shift first, aligning to bottom accessory
        let minX: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame, auxVerticalOffset: auxVerticalOffset).x }.min() ?? 0
        let maxX: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame, auxVerticalOffset: auxVerticalOffset).maxX }.max() ?? 0
        var minY: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame, auxVerticalOffset: auxVerticalOffset).y }.min() ?? 0
        var maxY: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame, auxVerticalOffset: auxVerticalOffset).maxY }.max() ?? 0
        minY = min(minY, previewFrame.minY)
        maxY = max(maxY, previewFrame.maxY)

        // Vertically shift if necessary
        if maxY > contentRect.maxY {
            let adjust = maxY - contentRect.maxY
            previewFrame.y -= adjust
            minY -= adjust
            maxY -= adjust
        }

        if minY < contentRect.minY {
            let adjust = contentRect.minY - minY
            previewFrame.y += adjust
            minY += adjust
            maxY += adjust
        }

        // Check if preview needs to be shrunk to to fit vertical accessories
        let contentHeight = maxY - minY
        var previewWidthAdjustment: CGFloat = 0
        if contentHeight > contentRect.height {
            let delta = contentHeight - contentRect.height
            let targetHeight = previewFrame.height - delta
            let scaleFactor = max((targetHeight / previewFrame.height), minPreviewScaleFactor)
            if previewViewAlignment == .right {
                let oldWidth = previewFrame.width
                previewFrame.size = CGSizeScale(previewFrame.size, scaleFactor)
                previewFrame.origin.x += oldWidth - previewFrame.width
                previewWidthAdjustment = oldWidth - previewFrame.width
            } else {
                previewFrame.size = CGSizeScale(previewFrame.size, scaleFactor)
            }
        }

        // Check if preview needs to be shrunk to fit horizontal accessories
        let contentWidth = maxX - minX - previewWidthAdjustment
        if contentWidth > contentRect.width {
            let delta = contentWidth - contentRect.width
            let targetWidth = previewFrame.width - delta
            let scaleFactor = max((targetWidth / previewFrame.width), minPreviewScaleFactor)
            if previewViewAlignment == .right {
                let oldWidth = previewFrame.width
                previewFrame.size = CGSizeScale(previewFrame.size, scaleFactor)
                previewFrame.origin.x += oldWidth - previewFrame.width
            } else {
                previewFrame.size = CGSizeScale(previewFrame.size, scaleFactor)
            }
        }

        return previewFrame
    }

    private func targetAuxiliaryPreviewFrame(previewFrame: CGRect) -> CGRect {
        guard let auxView = auxiliaryPreviewView else {
            return CGRect.zero
        }

        let auxSourceFrame = auxPreviewSourceFrame
        let previewSourceFrame = previewSourceFrame
        let scaleFactor = previewFrame.width / previewSourceFrame.width
        let originOffset = CGPointScale(CGPointSubtract(auxSourceFrame.origin, previewSourceFrame.origin), scaleFactor)
        var frame = auxView.frame
        frame.origin = CGPointAdd(originOffset, previewFrame.origin)
        frame.size = CGSizeScale(auxSourceFrame.size, scaleFactor)
        return frame
    }

    private func accessoryFrame(_ accessory: ContextMenuTargetedPreviewAccessory, previewFrame: CGRect, auxVerticalOffset: CGFloat) -> CGRect {
        var accessoryFrame = CGRect.zero
        accessory.accessoryView.sizeToFit()
        accessoryFrame.size = accessory.accessoryView.frame.size

        let isLandscape = UIDevice.current.isIPad ? false : bounds.size.width > bounds.size.height
        let defaultAlignments = accessory.accessoryAlignment.alignments
        let alignments = isLandscape ? accessory.landscapeAccessoryAlignment?.alignments ?? defaultAlignments : defaultAlignments

        for (edgeAlignment, originAlignment) in alignments {
            switch (edgeAlignment, originAlignment) {
            case (.top, .exterior):
                accessoryFrame.y = previewFrame.y - accessoryFrame.height
            case (.top, .interior):
                accessoryFrame.y = previewFrame.y
            case (.trailing, .exterior):
                accessoryFrame.x = previewFrame.maxX
            case (.trailing, .interior):
                accessoryFrame.x = previewFrame.maxX - accessoryFrame.width
            case (.leading, .exterior):
                accessoryFrame.x = previewFrame.x - accessoryFrame.width
            case (.leading, .interior):
                accessoryFrame.x = previewFrame.x
            case (.bottom, .exterior):
                accessoryFrame.y = previewFrame.maxY
                accessoryFrame.y += auxVerticalOffset
            case (.bottom, .interior):
                accessoryFrame.y = previewFrame.maxY - accessoryFrame.height
            }
        }

        if previewViewAlignment == .center {
            accessoryFrame.x = previewFrame.midX - (accessoryFrame.width / 2)
        }

        let defaultOffset = accessory.accessoryAlignment.alignmentOffset
        let offset = isLandscape ? accessory.landscapeAccessoryAlignment?.alignmentOffset ?? defaultOffset : defaultOffset
        accessoryFrame.origin = CGPointAdd(accessoryFrame.origin, offset)

        return accessoryFrame
    }

    private func adjustAccessoryFrameForContentRect(_ accessoryFrame: CGRect) -> CGRect {
        var updatedFrame = accessoryFrame
        // Adjust accessory horizontal/vertical overlap if needed
        let contentRect = bounds.inset(by: contentAreaInsets)
        if accessoryFrame.maxY > contentRect.maxY {
            let adjust = accessoryFrame.maxY - contentRect.maxY
            updatedFrame.y -= adjust
        }

        if accessoryFrame.maxX > contentRect.maxX {
            let adjust = accessoryFrame.maxX - contentRect.maxX
            updatedFrame.x -= adjust
        }

        return updatedFrame
    }

    private func layoutAccessoryView(_ accessory: ContextMenuTargetedPreviewAccessory, auxVerticalOffset: CGFloat) {
        let previewFrame = delegate?.contextMenuViewPreviewFrameForAccessoryLayout(self) ?? CGRect.zero
        accessory.accessoryView.frame = adjustAccessoryFrameForContentRect(accessoryFrame(accessory, previewFrame: previewFrame, auxVerticalOffset: auxVerticalOffset))
    }
}

class ContextMenuController: OWSViewController, ContextMenuViewDelegate, UIGestureRecognizerDelegate {
    weak var delegate: ContextMenuControllerDelegate?

    let contextMenuPreview: ContextMenuTargetedPreview
    let contextMenuConfiguration: ContextMenuConfiguration
    let menuAccessory: ContextMenuActionsAccessory?

    var previewView: UIView? {
        if let hostView = view as? ContextMenuHostView {
            return hostView.previewView
        }

        return nil
    }

    var auxiliaryPreviewView: UIView? {
        if let hostView = view as? ContextMenuHostView {
            return hostView.auxiliaryPreviewView
        }

        return nil
    }

    var gestureRecognizer: UIGestureRecognizer?
    var localPanGestureRecoginzer: UIPanGestureRecognizer?

    private let presentImmediately: Bool
    private let renderBackgroundBlur: Bool

    enum PreviewRenderMode {
        case shadow
        case fade
    }
    private let previewRenderMode: PreviewRenderMode

    private var gestureExitedDeadZone: Bool = false
    private let deadZoneRadius: CGFloat = 40
    private var initialTouchLocation: CGPoint?

    private var animationState: ContextMenuAnimationState = .none
    private var animateOutPreviewFrame = CGRect.zero
    private let animationDuration = 0.4
    private let springDamping: CGFloat = 0.8
    private let springInitialVelocity: CGFloat = 1.0

    private let dismissButton = UIButton(type: .custom)

    private var previewShadowVisible = false {
        didSet {
            self.previewView?.layer.shadowOpacity = previewShadowVisible ? 0.3 : 0
        }
    }

    var accessoryViews: [ContextMenuTargetedPreviewAccessory] {
        var accessories = contextMenuPreview.accessoryViews
        if let menuAccessory = self.menuAccessory {
            accessories.append(menuAccessory)
        }
        return accessories
    }

    lazy var blurView: UIVisualEffectView = {
        return UIVisualEffectView(effect: nil)
    }()

    private var emojiPickerSheet: EmojiPickerSheet?

    init (
        configuration: ContextMenuConfiguration,
        preview: ContextMenuTargetedPreview,
        initiatingGestureRecognizer: UIGestureRecognizer?,
        menuAccessory: ContextMenuActionsAccessory?,
        presentImmediately: Bool = true,
        renderBackgroundBlur: Bool = true,
        previewRenderMode: PreviewRenderMode = .shadow
    ) {
        self.contextMenuConfiguration = configuration
        self.contextMenuPreview = preview
        self.gestureRecognizer = initiatingGestureRecognizer
        self.menuAccessory = menuAccessory
        self.presentImmediately = presentImmediately
        self.renderBackgroundBlur = renderBackgroundBlur
        self.previewRenderMode = previewRenderMode
        super.init()
        if #available(iOS 13, *), configuration.forceDarkTheme { overrideUserInterfaceStyle = .dark }
    }

    // MARK: UIViewController

    override func loadView() {
        let contextMenuView = ContextMenuHostView(frame: CGRect.zero)
        contextMenuView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contextMenuView.delegate = self
        contextMenuView.previewViewAlignment = contextMenuPreview.alignment
        view = contextMenuView

        view.accessibilityViewIsModal = true

        dismissButton.isAccessibilityElement = true
        dismissButton.accessibilityLabel = NSLocalizedString("DISMISS_CONTEXT_MENU", comment: "Dismiss context menu accessibility label")
        dismissButton.addTarget(self, action: #selector(dismissButtonTapped(sender:)), for: .touchUpInside)
        contextMenuView.blurView = blurView
        contextMenuView.dismissButton = dismissButton
        contextMenuView.previewView = contextMenuPreview.previewView
        contextMenuView.previewView?.isAccessibilityElement = true
        contextMenuView.previewView?.accessibilityLabel = NSLocalizedString("MESSAGE_PREVIEW", comment: "Context menu message preview accessibility label")
        contextMenuView.auxiliaryPreviewView = contextMenuPreview.auxiliarySnapshot
        contextMenuView.auxiliaryPreviewView?.isAccessibilityElement = false
        contextMenuView.accessoryViews = accessoryViews

        self.previewView?.isUserInteractionEnabled = false
        self.previewView?.isHidden = true
        self.previewView?.layer.shadowRadius = 12
        self.previewView?.layer.shadowOffset = CGSize(width: 0, height: 4)
        self.previewView?.layer.shadowColor = UIColor.ows_black.cgColor
        self.previewView?.layer.shadowOpacity = 0

        self.auxiliaryPreviewView?.isHidden = true

        for accessory in accessoryViews {
            if accessory.animateAccessoryPresentationAlongsidePreview {
                accessory.accessoryView.isHidden = true
            }
        }
    }

    @objc
    private func dismissButtonTapped(sender: UIButton) {
        delegate?.contextMenuControllerRequestsDismissal(self)
    }

    private lazy var presentedSize = view.bounds.size
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard let superview = view.superview, presentedSize != superview.bounds.size else { return }

        delegate?.contextMenuControllerRequestsDismissal(self)

        // TODO: Support orientation changes.
        // We can't use `viewWillTransition(to:with:)` here because we're added directly to the window
    }

    override func applyTheme() {
        super.applyTheme()
        delegate?.contextMenuControllerRequestsDismissal(self)

        // TODO: Support theme changes
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let previewView = previewView else {
            owsFailDebug("Cannot animate without preview view!")
            return
        }

        animationState = .animateIn

        UIView.animate(withDuration: animationDuration / 2.0) {
            if self.renderBackgroundBlur {
                if !UIDevice.current.isIPad {
                    self.blurView.effect = UIBlurEffect(style: UIBlurEffect.Style.regular)
                    self.blurView.backgroundColor = self.contextMenuConfiguration.forceDarkTheme || Theme.isDarkThemeEnabled ? UIColor.ows_whiteAlpha20 : UIColor.ows_blackAlpha20
                } else {
                    self.blurView.backgroundColor = UIColor.ows_blackAlpha40
                }
            }

            switch self.previewRenderMode {
            case .shadow:
                self.previewShadowVisible = true
            case .fade:
                self.previewView?.alpha = 0.5
            }
        }

        let finalFrame = previewView.frame
        let initialFrame = previewSourceFrame()
        let shiftPreview = finalFrame != initialFrame

        // Match initial transform
        if !presentImmediately {
            previewView.transform = CGAffineTransform.scale(0.95)
        }

        previewView.isHidden = false
        auxiliaryPreviewView?.isHidden = false

        for accessory in accessoryViews {
            if accessory.animateAccessoryPresentationAlongsidePreview {
                accessory.accessoryView.isHidden = false
            }
        }
        contextMenuPreview.view.isHidden = true
        contextMenuPreview.auxiliaryView?.isHidden = true

        if shiftPreview {
            previewView.frame = initialFrame

            let finalAuxFrame = auxiliaryPreviewView?.frame ?? CGRect.zero
            auxiliaryPreviewView?.frame = auxPreviewSourceFrame()

            let yDelta = finalFrame.y - initialFrame.y
            let heightDelta = finalFrame.height - initialFrame.height
            for accessory in accessoryViews {
                if accessory.animateAccessoryPresentationAlongsidePreview {
                    accessory.accessoryView.frame.y -= (yDelta + heightDelta)
                }
            }

            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: springDamping,
                initialSpringVelocity: springInitialVelocity,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    for accessory in self.accessoryViews {
                        if accessory.animateAccessoryPresentationAlongsidePreview {
                            accessory.accessoryView.frame.y += (yDelta + heightDelta)
                        }
                    }
                    self.previewView?.frame = finalFrame
                    self.previewView?.transform = CGAffineTransform.identity

                    self.auxiliaryPreviewView?.frame = finalAuxFrame
                }) { _ in
                    self.animationState = .none
                    UIAccessibility.post(notification: .layoutChanged, argument: self.dismissButton)
            }
        } else {
            // Re-scale to match original size, on the original scaling curve
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    self.previewView?.transform = CGAffineTransform.identity
                },
                completion: nil
            )
        }

        // Animate in accessories
        for accessory in accessoryViews {
            accessory.animateIn(duration: animationDuration, previewWillShift: shiftPreview) { }
        }
    }

    // MARK: Public

    public func animateOut(_ completion: @escaping () -> Void) {

        guard let previewView = previewView else {
            owsFailDebug("Cannot animate without preview view!")
            completion()
            return
        }

        let dispatchGroup = DispatchGroup()
        animationState = .animateOut

        dispatchGroup.enter()
        UIView.animate(withDuration: animationDuration) {
            if self.renderBackgroundBlur {
                self.blurView.effect = nil
                self.blurView.backgroundColor = nil
            }

            switch self.previewRenderMode {
            case .shadow:
                self.previewShadowVisible = false
            case .fade:
                self.previewView?.alpha = 1
            }
        } completion: { _ in
            dispatchGroup.leave()
        }

        let finalFrame = previewSourceFrame()
        let initialFrame = previewView.frame
        animateOutPreviewFrame = initialFrame
        let shiftPreview = finalFrame != initialFrame
        if shiftPreview {

            let yDelta = finalFrame.y - initialFrame.y
            let heightDelta = finalFrame.height - initialFrame.height
            dispatchGroup.enter()
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: springDamping,
                initialSpringVelocity: springInitialVelocity,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    for accessory in self.accessoryViews {
                        if accessory.animateAccessoryPresentationAlongsidePreview {
                            var frame = accessory.accessoryView.frame
                            frame.y += (yDelta + heightDelta)
                            accessory.accessoryView.frame = frame
                            accessory.targetAnimateOutFrame = frame
                        }
                    }
                    self.previewView?.frame = finalFrame
                    self.auxiliaryPreviewView?.frame = self.auxPreviewSourceFrame()
                },
                completion: { _ in
                    dispatchGroup.leave()
                }
            )
        }

        // Animate in accessories
        for accessory in accessoryViews {
            dispatchGroup.enter()
            accessory.animateOut(duration: animationDuration, previewWillShift: shiftPreview) {
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.contextMenuPreview.view.isHidden = false
            self.contextMenuPreview.auxiliaryView?.isHidden = false
            self.animationState = .none
            completion()
        }
    }

    // MARK: Gesture Recognizer Support
    public func gestureDidChange() {
        guard !UIAccessibility.isVoiceOverRunning else {
            return
        }

        if let locationInView = gestureRecognizer?.location(in: view) {

            if !gestureExitedDeadZone {
                guard let initialTouchLocation = self.initialTouchLocation else {
                    self.initialTouchLocation = locationInView
                    return
                }

                let distanceFromInitialLocation = abs(hypot(
                    locationInView.x - initialTouchLocation.x,
                    locationInView.y - initialTouchLocation.y
                ))
                gestureExitedDeadZone = distanceFromInitialLocation >= deadZoneRadius

                if !gestureExitedDeadZone { return }
            }

            for accessory in accessoryViews {
                let locationInAccessory = view .convert(locationInView, to: accessory.accessoryView)
                accessory.touchLocationInViewDidChange(locationInView: locationInAccessory)
            }
        }

    }

    public func gestureDidEnd() {
        guard !UIAccessibility.isVoiceOverRunning else {
            return
        }

        handleGestureEnd()
    }

    private func handleGestureEnd() {
        if localPanGestureRecoginzer == nil {
            if let gestureRecognizer = self.gestureRecognizer {
                view.removeGestureRecognizer(gestureRecognizer)
            }

            let newPanGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognized(sender:)))
            view.addGestureRecognizer(newPanGesture)
            gestureRecognizer = newPanGesture
            localPanGestureRecoginzer = newPanGesture
        }

        if !gestureExitedDeadZone { return }

        var accessoryHandledTouch = false
        if let locationInView = gestureRecognizer?.location(in: view) {
            for accessory in accessoryViews {
                let locationInAccessory = view .convert(locationInView, to: accessory.accessoryView)
                let handled = accessory.touchLocationInViewDidEnd(locationInView: locationInAccessory)
                if !accessoryHandledTouch {
                    accessoryHandledTouch = handled
                }
            }
        }

        if !accessoryHandledTouch {
            delegate?.contextMenuControllerRequestsDismissal(self)
            return
        }
    }

    // MARK: Emoji Sheet
    public func showEmojiSheet(completion: @escaping (String) -> Void) {
        let picker = EmojiPickerSheet { [weak self] emoji in
            guard let self = self else { return }

            guard let emojiString = emoji?.rawValue else {
                self.delegate?.contextMenuControllerRequestsDismissal(self)
                return
            }

            completion(emojiString)
        }
        picker.externalBackdropView = blurView
        emojiPickerSheet = picker
        present(picker, animated: true)
    }

    public func dismissEmojiSheet(animated: Bool, completion: @escaping () -> Void) {
        emojiPickerSheet?.dismiss(animated: true, completion: completion)
    }

    // MARK: ContextMenuViewDelegate

    fileprivate func contextMenuViewPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect {
        return previewSourceFrame()
    }

    fileprivate func contextMenuViewAuxPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect {
        return auxPreviewSourceFrame()
    }

    fileprivate func contextMenuViewAnimationState(_ contextMenuView: ContextMenuHostView) -> ContextMenuAnimationState {
        return animationState
    }

    fileprivate func contextMenuViewPreviewFrameForAccessoryLayout(_ contextMenuView: ContextMenuHostView) -> CGRect {
        if animationState == .animateOut {
            return animateOutPreviewFrame
        }

        return previewView?.frame ?? CGRect.zero
    }

    // MARK: Private

    private func previewSourceFrame() -> CGRect {
        return view.convert(contextMenuPreview.previewViewSourceFrame, from: contextMenuPreview.view.superview)
    }

    private func auxPreviewSourceFrame() -> CGRect {
        guard let auxPreview = contextMenuPreview.auxiliaryView else {
            return CGRect.zero
        }

        return view.convert(auxPreview.frame, from: auxPreview.superview)
    }

    @objc
    private func panGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            gestureDidChange()
        } else if sender.state == .ended {
            handleGestureEnd()
        }
    }

}
