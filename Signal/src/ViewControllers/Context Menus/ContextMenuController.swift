//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuControllerDelegate: AnyObject {
    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController)
}

private protocol ContextMenuViewDelegate: AnyObject {
    func contextMenuViewPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect
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
        let constPadding: CGFloat = 22
        let minHorizPadding: CGFloat = 16
        return UIEdgeInsets(top: safeAreaInsets.top + constPadding,
                     leading: max(safeAreaInsets.leading, minHorizPadding),
                     bottom: safeAreaInsets.bottom + constPadding,
                     trailing: max(safeAreaInsets.trailing, minHorizPadding))
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

    lazy var previewSourceFrame: CGRect = delegate?.contextMenuViewPreviewSourceFrame(self) ?? CGRect.zero
    private let minPreviewScaleFactor: CGFloat = 0.5

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView?.frame = bounds

        let animationState = delegate?.contextMenuViewAnimationState(self) ?? .none

        if let previewView = self.previewView {
            // Let the controller manage the preview's frame if animating
            if animationState != .animateOut {
                previewView.frame = targetPreviewFrame()
            }
        }

        if let accessories = accessoryViews {
            for accessory in accessories {
                layoutAccessoryView(accessory)
            }
        }
    }

    private func targetPreviewFrame() -> CGRect {
        var previewFrame = previewSourceFrame
        let contentRect = bounds.inset(by: contentAreaInsets)

        // Check for Y-offset shift first, aligning to bottom accessory
        let minX: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame).x }.min() ?? 0
        let maxX: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame).maxX }.max() ?? 0
        var minY: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame).y }.min() ?? 0
        var maxY: CGFloat = accessoryViews?.map { accessoryFrame($0, previewFrame: previewFrame).maxY }.max() ?? 0
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

    private func accessoryFrame(_ accessory: ContextMenuTargetedPreviewAccessory, previewFrame: CGRect) -> CGRect {
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

    private func layoutAccessoryView(_ accessory: ContextMenuTargetedPreviewAccessory) {
        let previewFrame = delegate?.contextMenuViewPreviewFrameForAccessoryLayout(self) ?? CGRect.zero

        let animationState = delegate?.contextMenuViewAnimationState(self) ?? .none
        guard !(accessory.animateAccessoryPresentationAlongsidePreview && animationState == .animateOut) else {
            return
        }

        accessory.accessoryView.frame = adjustAccessoryFrameForContentRect(accessoryFrame(accessory, previewFrame: previewFrame))
    }
}

class ContextMenuController: UIViewController, ContextMenuViewDelegate, UIGestureRecognizerDelegate {
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

    var gestureRecognizer: UIGestureRecognizer?
    var localPanGestureRecoginzer: UIPanGestureRecognizer?

    private var gestureExitedDeadZone: Bool = false
    private let deadZoneRadius: CGFloat = 30
    private var initialTouchLocation: CGPoint?

    private var animationState: ContextMenuAnimationState = .none
    private var animateOutPreviewFrame = CGRect.zero
    private let animationDuration = 0.4
    private let springDamping: CGFloat = 0.8
    private let springInitialVelocity: CGFloat = 1.0

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
        menuAccessory: ContextMenuActionsAccessory?
    ) {
        self.contextMenuConfiguration = configuration
        self.contextMenuPreview = preview
        self.gestureRecognizer = initiatingGestureRecognizer
        self.menuAccessory = menuAccessory

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func loadView() {
        let contextMenuView = ContextMenuHostView(frame: CGRect.zero)
        contextMenuView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contextMenuView.delegate = self
        contextMenuView.previewViewAlignment = contextMenuPreview.alignment
        view = contextMenuView

        contextMenuView.blurView = blurView
        contextMenuView.previewView = contextMenuPreview.snapshot
        contextMenuView.accessoryViews = accessoryViews

        self.previewView?.isHidden = true
        self.previewView?.layer.shadowRadius = 12
        self.previewView?.layer.shadowOffset = CGSize(width: 0, height: 4)
        self.previewView?.layer.shadowColor = UIColor.ows_black.cgColor

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecognized(sender:)))
        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        blurView.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let previewView = previewView else {
            owsFailDebug("Cannot animate without preview view!")
            return
        }

        animationState = .animateIn

        UIView.animate(withDuration: animationDuration / 2.0) {
            if !UIDevice.current.isIPad {
                self.blurView.effect = UIBlurEffect(style: UIBlurEffect.Style.regular)
                self.blurView.backgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_whiteAlpha20 : UIColor.ows_blackAlpha20
            } else {
                self.blurView.backgroundColor = UIColor.ows_blackAlpha40
            }
            self.previewShadowVisible = true
        }

        let finalFrame = previewView.frame
        let initialFrame = previewSourceFrame()
        let shiftPreview = finalFrame != initialFrame

        // Match initial transform
        previewView.transform = CGAffineTransform.scale(0.95)
        previewView.isHidden = false
        contextMenuPreview.view?.isHidden = true

        if shiftPreview {
            previewView.frame = initialFrame

            let yDelta = finalFrame.y - initialFrame.y
            for accessory in accessoryViews {
                if accessory.animateAccessoryPresentationAlongsidePreview {
                    accessory.accessoryView.frame.y -= yDelta
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
                            accessory.accessoryView.frame.y += yDelta
                        }
                    }
                    self.previewView?.frame = finalFrame
                    self.previewView?.transform = CGAffineTransform.identity
                }) { _ in
                    self.animationState = .none
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
        UIView.animate(withDuration: animationDuration / 2.0) {
            self.blurView.effect = nil
            self.blurView.backgroundColor = nil
            self.previewShadowVisible = false
        } completion: { _ in
            dispatchGroup.leave()
        }

        let finalFrame = previewSourceFrame()
        let initialFrame = previewView.frame
        animateOutPreviewFrame = initialFrame
        let shiftPreview = finalFrame != initialFrame
        if shiftPreview {

            let yDelta = finalFrame.y - initialFrame.y

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
                            accessory.accessoryView.frame.y += yDelta
                        }
                    }
                    self.previewView?.frame = finalFrame
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
            self.contextMenuPreview.view?.isHidden = false
            self.animationState = .none
            completion()
        }
    }

    // MARK: Gesture Recognizer Support
    public func gestureDidChange() {
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
        guard localPanGestureRecoginzer == nil else {
            return
        }

        handleGestureEnd()
    }

    private func handleGestureEnd() {
        if !gestureExitedDeadZone { return }

        if let locationInView = gestureRecognizer?.location(in: view) {
            for accessory in accessoryViews {
                let locationInAccessory = view .convert(locationInView, to: accessory.accessoryView)
                accessory.touchLocationInViewDidEnd(locationInView: locationInAccessory)
            }
        }

        if localPanGestureRecoginzer == nil {
            if let gestureRecognizer = self.gestureRecognizer {
                view.removeGestureRecognizer(gestureRecognizer)
            }

            let newPanGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognized(sender:)))
            view.addGestureRecognizer(newPanGesture)
            gestureRecognizer = newPanGesture
            localPanGestureRecoginzer = newPanGesture
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
        guard let sourceView = contextMenuPreview.view else {
            owsFailDebug("Expected source view")
            return CGRect.zero
        }
        return view.convert(sourceView.frame, from: sourceView.superview)
    }

    @objc
    private func tapGestureRecognized(sender: UIGestureRecognizer) {
        delegate?.contextMenuControllerRequestsDismissal(self)
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
