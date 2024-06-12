//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

enum CallMemberVisualContext: Equatable {
    case videoGrid, videoOverflow, speaker
}

protocol CallMemberComposableView: UIView {
    func configure(
        call: SignalCall,
        isFullScreen: Bool,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    )
    func rotateForPhoneOrientation(_ rotationAngle: CGFloat)
    func updateDimensions()
    func clearConfiguration()
}

class CallMemberView: UIView {
    private let callMemberCameraOffView: CallMemberCameraOffView
    private let callMemberWaitingAndErrorView: CallMemberWaitingAndErrorView
    private let callMemberChromeOverlayView: CallMemberChromeOverlayView

    /// This view is "associated" because it is not actually part of `CallMemberView`'s
    /// view hierarchy. The original intent was to have this view be a subview, just like
    /// any other `CallMemberComposableView`. Unfortunately, it was very difficult get
    /// this view's layer to animate (see `animatePip` method) properly with this setup.
    /// So instead, the view that instantiates a `CallMemberView` also instantiates
    /// `CallMemberVideoView` and arranges the two as siblings in the view hierarchy. In
    /// somewhat of an architectural hack, `CallMemberView` still manages updates an 
    /// animations of `_associatedCallMemberVideoView`.
    private let _associatedCallMemberVideoView: CallMemberVideoView
    private var composableViews = [CallMemberComposableView]()

    private let type: MemberType
    private var call: SignalCall?

    // Properties relating to local member pip expansions/contractions.
    private var shouldAllowTapHandling: Bool?
    private var isPipAnimationInProgress = false
    private var isPipExpanded: Bool = false

    weak var animatableLocalMemberViewDelegate: AnimatableLocalMemberViewDelegate?

    init(type: MemberType) {
        self.type = type
        self.callMemberCameraOffView = CallMemberCameraOffView(type: type)
        self.callMemberWaitingAndErrorView = CallMemberWaitingAndErrorView(type: type)
        self.callMemberChromeOverlayView = CallMemberChromeOverlayView(type: type)

        self._associatedCallMemberVideoView = CallMemberVideoView(type: type)

        super.init(frame: .zero)
        self.backgroundColor = .clear
        let orderedComposableViews: [CallMemberComposableView]
        switch type {
        case .local, .remoteInIndividual:
            orderedComposableViews = [
                callMemberCameraOffView,
                callMemberChromeOverlayView
            ]
        case .remoteInGroup:
            orderedComposableViews = [
                callMemberCameraOffView,
                callMemberWaitingAndErrorView,
                callMemberChromeOverlayView
            ]
        }

        let tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(callMemberViewWasTapped)
        )
        self.addGestureRecognizer(tapGestureRecognizer)

        clipsToBounds = true

        orderedComposableViews.forEach { view in
            self.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()
        }

        self.composableViews = orderedComposableViews + [self._associatedCallMemberVideoView]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateOrientationForPhone),
            name: CallService.phoneOrientationDidChange,
            object: nil
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self {
            switch self.type {
            case .remoteInGroup(_), .remoteInIndividual(_):
                return nil
            case .local:
                if self.shouldAllowTapHandling == true {
                    return view
                }
                return nil
            }
        }
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDimensions()
    }

    @objc
    private func updateOrientationForPhone(_ notification: Notification) {
        let rotationAngle = notification.object as! CGFloat

        if window == nil {
            self.composableViews.forEach { view in
                view.rotateForPhoneOrientation(rotationAngle)
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.composableViews.forEach { view in
                    view.rotateForPhoneOrientation(rotationAngle)
                }
            }
        }
    }

    enum MemberType {
        case local
        case remoteInGroup(CallMemberVisualContext)
        case remoteInIndividual(IndividualCall)
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        remoteGroupMemberDeviceState: RemoteDeviceState? = nil
    ) {
        self.call = call
        self.shouldAllowTapHandling = !isFullScreen
        switch self.type {
        case .local:
            owsAssertDebug(remoteGroupMemberDeviceState == nil, "RemoteDeviceStates are only applicable to remote members in group calls!")
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 4
            layer.cornerRadius = isFullScreen ? 0 : Constants.defaultPipCornerRadius
        case .remoteInGroup:
            owsAssertDebug(remoteGroupMemberDeviceState != nil, "RemoteDeviceState must be given for remote members in group calls!")
        case .remoteInIndividual:
            owsAssertDebug(remoteGroupMemberDeviceState == nil, "RemoteDeviceStates are only applicable to group calls!")
        }

        self.composableViews.forEach { view in
            view.configure(
                call: call,
                isFullScreen: isFullScreen,
                remoteGroupMemberDeviceState: remoteGroupMemberDeviceState
            )
        }
    }

    private func updateDimensions() {
        self.composableViews.forEach { view in
            view.updateDimensions()
        }
    }

    func clearConfiguration() {
        self.composableViews.forEach { view in
            view.clearConfiguration()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var associatedCallMemberVideoView: CallMemberVideoView? {
        return self._associatedCallMemberVideoView
    }

    func cleanupVideoViews() {
        self._associatedCallMemberVideoView.clearConfiguration()
    }

    func configureRemoteVideo(device: RemoteDeviceState, context: CallMemberVisualContext) {
        self._associatedCallMemberVideoView.configureRemoteVideo(
            device: device,
            context: context
        )
    }

    /// Applies the changes in the `apply` block to both the `CallMemberView` and
    /// its `associatedCallMemberVideoView`. (See documentation of the latter to
    /// understand why it is not simply a subview of the former. The tl;dr is:
    /// pip animations were finicky and much easier to get right with these views
    /// as siblings.) Since many layout changes made to `CallMemberView` also need
    /// to be made to `associatedCallMemberVideoView`, this method acts a convenience
    /// wrapper to apply the changes to both at once.
    ///
    /// - Parameter startWithVideoView: Whether the `apply` block should be applied first
    ///   to the `associatedCallMemberVideoView` and then to the `CallMemberView`. For
    ///   example, the order matters when `apply` includes adding subviews. Generally, we
    ///   want the video view to sit underneath the `CallMemberView`.
    /// - Parameter apply: The block that will be applied to each UIView - the `CallMemberView`
    ///   and the `associatedCallMemberVideoView`.
    func applyChangesToCallMemberViewAndVideoView(startWithVideoView: Bool = true, apply: (UIView) -> Void) {
        if startWithVideoView {
            apply(self._associatedCallMemberVideoView)
            apply(self)
        } else {
            apply(self)
            apply(self._associatedCallMemberVideoView)
        }
    }

    var isCallMinimized: Bool {
        get {
            self.callMemberWaitingAndErrorView.isCallMinimized
        }
        set {
            self.callMemberWaitingAndErrorView.isCallMinimized = newValue
        }
    }

    weak var errorPresenter: CallMemberErrorPresenter? {
        get {
            self.callMemberWaitingAndErrorView.errorPresenter
        }
        set {
            self.callMemberWaitingAndErrorView.errorPresenter = newValue
        }
    }

    var isGroupCall: Bool {
        get {
            if let remoteVideoView {
                return remoteVideoView.isGroupCall
            }
            return false
        }
        set {
            if let remoteVideoView {
                remoteVideoView.isGroupCall = newValue
            }
        }
    }

    var isScreenShare: Bool {
        get {
            if let remoteVideoView {
                return remoteVideoView.isScreenShare
            }
            return false
        }
        set {
            if let remoteVideoView {
                remoteVideoView.isScreenShare = newValue
            }
        }
    }

    var isFullScreen: Bool {
        get {
            if let remoteVideoView {
                return remoteVideoView.isFullScreen
            }
            return false
        }
        set {
            if let remoteVideoView {
                remoteVideoView.isFullScreen = newValue
            }
        }
    }

    var remoteVideoView: RemoteVideoView? {
        if let remoteVideoView = self._associatedCallMemberVideoView.remoteVideoViewIfApplicable() {
            return remoteVideoView
        }
        return nil
    }
}

// MARK: - Local View Gesture Handling

extension CallMemberView: UIGestureRecognizerDelegate {
    private func callMemberVideoViewAnchorPoint(for nearestCorner: Corner) -> CGPoint {
        switch nearestCorner {
        case .upperLeft:
            return CGPoint(x: 0, y: 0)
        case .upperRight:
            return CGPoint(x: 1, y: 0)
        case .lowerLeft:
            return CGPoint(x: 0, y: 1)
        case .lowerRight:
            return CGPoint(x: 1, y: 1)
        }
    }

    private func animatePip(fromFrame: CGRect, isExpanding: Bool) {
        guard shouldAllowTapHandling == true, !isPipAnimationInProgress else {
            return
        }
        let nearestCorner = nearestCorner(innerFrame: self.frame, memberType: .local)
        let toFrame: CGRect
        if isExpanding {
            guard
                let call,
                // The design concept is that the pip expands, thereby
                // enabling the flip camera button. So if the camera
                // is off, there's no need for the expansion.
                !call.isOutgoingVideoMuted
            else {
                return
            }
            toFrame = self.enlargedFrame(
                startingFrame: fromFrame,
                anchorCorner: nearestCorner
            )
        } else {
            toFrame = self.shrunkenFrame(
                currentFrame: fromFrame,
                anchorCorner: nearestCorner
            )
        }

        guard fromFrame.size != toFrame.size else {
            // An optimization. When there are two members in a call on iPad,
            // the PIP is already at size.
            return
        }

        self.associatedCallMemberVideoView?.layer.anchorPoint = callMemberVideoViewAnchorPoint(for: nearestCorner)
        let animator = UIViewPropertyAnimator(
            duration: 0.3,
            springDamping: 1,
            springResponse: 0.3
        )

        let scaleX = toFrame.width/fromFrame.width
        let scaleY = toFrame.height/fromFrame.height
        animator.addAnimations {
            self.frame = toFrame
            self._associatedCallMemberVideoView.transform = CGAffineTransform(
                scaleX: scaleX,
                y: scaleY
            )
        }

        self._associatedCallMemberVideoView.frame = fromFrame
        self._associatedCallMemberVideoView.layer.cornerRadius = Constants.defaultPipCornerRadius
        self.animatableLocalMemberViewDelegate?.animatableLocalMemberViewWillBeginAnimation(self)
        self.isPipAnimationInProgress = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            /// Disabling actions disables default system animations of the below properties,
            /// which, if left enabled, create a visual "jolt" at the end of the animation.
            self._associatedCallMemberVideoView.transform = .identity
            self._associatedCallMemberVideoView.frame = toFrame
            self._associatedCallMemberVideoView.layer.cornerRadius = Constants.defaultPipCornerRadius
            CATransaction.commit()

            self.isPipExpanded = isExpanding
            self.isPipAnimationInProgress = false
            if isExpanding {
                self.animatableLocalMemberViewDelegate?.animatableLocalMemberViewDidCompleteExpandAnimation(self)
            } else {
                self.animatableLocalMemberViewDelegate?.animatableLocalMemberViewDidCompleteShrinkAnimation(self)
            }
        }

        animator.startAnimation()

        let toCornerRadius = Constants.defaultPipCornerRadius/scaleX
        let cornerAnimation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))
        cornerAnimation.fromValue = Constants.defaultPipCornerRadius
        cornerAnimation.toValue = toCornerRadius
        cornerAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cornerAnimation.duration = 0.3
        self._associatedCallMemberVideoView.layer.cornerRadius = toCornerRadius
        self._associatedCallMemberVideoView.layer.add(cornerAnimation, forKey: #keyPath(CALayer.cornerRadius))
        CATransaction.commit()
    }

    @objc
    fileprivate func callMemberViewWasTapped() {
        switch self.type {
        case .local:
            animatePip(fromFrame: self.frame, isExpanding: !self.isPipExpanded)
        case .remoteInGroup, .remoteInIndividual:
            return
        }
    }

    // MARK: Frame Math

    enum Constants {
        static let enlargedPipWidth: CGFloat = 170
        fileprivate static let enlargedPipHeight: CGFloat = 300
        static let enlargedPipWidthIpadLandscape: CGFloat = 272
        fileprivate static let enlargedPipHeightIpadLandscape: CGFloat = 204
        fileprivate static let enlargedPipWidthIpadPortrait: CGFloat = 204
        fileprivate static let enlargedPipHeightIpadPortrait: CGFloat = 272
        static let defaultPipCornerRadius: CGFloat = 10
    }

    private var enlargedPipSize: CGSize {
        if UIDevice.current.isIPad {
            if self.frame.width > self.frame.height {
                return CGSize(
                    width: Constants.enlargedPipWidthIpadLandscape,
                    height: Constants.enlargedPipHeightIpadLandscape
                )
            } else {
                return CGSize(
                    width: Constants.enlargedPipWidthIpadPortrait,
                    height: Constants.enlargedPipHeightIpadPortrait
                )
            }
        } else {
            return CGSize(
                width: Constants.enlargedPipWidth,
                height: Constants.enlargedPipHeight
            )
        }
    }

    private func enlargedFrame(
        startingFrame: CGRect,
        anchorCorner: Corner
    ) -> CGRect {
        let enlargedPipSize = enlargedPipSize
        switch anchorCorner {
        case .upperLeft:
            return CGRect(
                origin: startingFrame.origin,
                size: CGSize(width: enlargedPipSize.width, height: enlargedPipSize.height)
            )
        case .upperRight:
            return CGRect(
                x: startingFrame.x - (enlargedPipSize.width - startingFrame.width),
                y: startingFrame.y,
                width: enlargedPipSize.width,
                height: enlargedPipSize.height
            )
        case .lowerLeft:
            return CGRect(
                x: startingFrame.x,
                y: startingFrame.y - (enlargedPipSize.height - startingFrame.height),
                width: enlargedPipSize.width,
                height: enlargedPipSize.height
            )
        case .lowerRight:
            return CGRect(
                x: startingFrame.x - (enlargedPipSize.width - startingFrame.width),
                y: startingFrame.y - (enlargedPipSize.height - startingFrame.height),
                width: enlargedPipSize.width,
                height: enlargedPipSize.height
            )
        }
    }

    private func shrunkenFrame(
        currentFrame: CGRect,
        anchorCorner: Corner
    ) -> CGRect {
        let newSize = Self.pipSize(
            expandedPipFrame: nil,
            remoteDeviceCount: animatableLocalMemberViewDelegate?.remoteDeviceCount ?? 1
        )
        switch anchorCorner {
        case .upperLeft:
            return CGRect(
                origin: currentFrame.origin,
                size: newSize
            )
        case .upperRight:
            return CGRect(
                origin: CGPoint(
                    x: currentFrame.x + (currentFrame.width - newSize.width),
                    y: currentFrame.y
                ),
                size: newSize
            )
        case .lowerLeft:
            return CGRect(
                origin: CGPoint(
                    x: currentFrame.x,
                    y: currentFrame.y + (currentFrame.height - newSize.height)
                ),
                size: newSize
            )
        case .lowerRight:
            return CGRect(
                origin: CGPoint(
                    x: currentFrame.x + (currentFrame.width - newSize.width),
                    y: currentFrame.y + (currentFrame.height - newSize.height)
                ),
                size: newSize
            )
        }
    }

    private enum Corner {
        case upperLeft
        case upperRight
        case lowerLeft
        case lowerRight
    }

    private func nearestCorner(
        innerFrame: CGRect,
        memberType: MemberType
    ) -> Corner {
        switch memberType {
        case .local:
            guard let outerBounds = self.animatableLocalMemberViewDelegate?.enclosingBounds else { return .upperRight }
            let innerFrameCenter = CGPoint(
                x: innerFrame.x + innerFrame.width/2.0,
                y: innerFrame.y + innerFrame.height/2.0
            )
            let distanceSquaredFromUpperLeft = distanceSquared(
                x1: innerFrameCenter.x,
                x2: outerBounds.x,
                y1: innerFrameCenter.y,
                y2: outerBounds.y
            )
            let distanceSquaredFromUpperRight = distanceSquared(
                x1: innerFrameCenter.x,
                x2: outerBounds.width,
                y1: innerFrameCenter.y,
                y2: outerBounds.y
            )
            let distanceSquaredFromLowerLeft = distanceSquared(
                x1: innerFrameCenter.x,
                x2: outerBounds.x,
                y1: innerFrameCenter.y,
                y2: outerBounds.height
            )
            let distanceSquaredFromLowerRight = distanceSquared(
                x1: innerFrameCenter.x,
                x2: outerBounds.width,
                y1: innerFrameCenter.y,
                y2: outerBounds.height
            )

            let choices = [
                (Corner.upperLeft, distanceSquaredFromUpperLeft),
                (Corner.upperRight, distanceSquaredFromUpperRight),
                (Corner.lowerLeft, distanceSquaredFromLowerLeft),
                (Corner.lowerRight, distanceSquaredFromLowerRight)
            ]

            var min = CGFloat.infinity
            var nearestCorner = Corner.upperLeft
            for (choice, distance) in choices {
                if distance < min {
                    min = distance
                    nearestCorner = choice
                }
            }
            return nearestCorner
        case .remoteInGroup, .remoteInIndividual:
            // Pip in group calls is fixed in lower right corner.
            return .lowerRight
        }
    }

    private func distanceSquared(
        x1: CGFloat,
        x2: CGFloat,
        y1: CGFloat,
        y2: CGFloat
    ) -> CGFloat {
        pow((x1 - x2), 2) + pow((y1 - y2), 2)
    }

    static func pipSize(
        expandedPipFrame: CGRect?,
        remoteDeviceCount: Int
    ) -> CGSize {
        if let expandedPipFrame {
            if UIDevice.current.isIPad {
                return ReturnToCallViewController.inherentPipSize
            } else {
                return expandedPipFrame.size
            }
        } else {
            if remoteDeviceCount > 1 {
                let pipWidth = GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.inherentPipSize.aspectRatio
                let pipHeight = GroupCallVideoOverflow.itemHeight
                return CGSize(width: pipWidth, height: pipHeight)
            } else {
                return ReturnToCallViewController.inherentPipSize
            }
        }
    }
}

/// For local member pip expansion and contraction animations.
protocol AnimatableLocalMemberViewDelegate: AnyObject {
    /// The bounds of the view that the local `CallMemberView` pip is laid out relative to.
    /// This will typically be the bounds of the superview.
    var enclosingBounds: CGRect { get }

    /// The number of members in the call, excluding the local user.
    var remoteDeviceCount: Int { get }

    /// Called when the expansion animation completes.
    func animatableLocalMemberViewDidCompleteExpandAnimation(_ localMemberView: CallMemberView)

    /// Called when the contraction animation completes.
    func animatableLocalMemberViewDidCompleteShrinkAnimation(_ localMemberView: CallMemberView)

    /// Called right before a contraction or expansion animation is triggered.
    func animatableLocalMemberViewWillBeginAnimation(_ localMemberView: CallMemberView)
}
