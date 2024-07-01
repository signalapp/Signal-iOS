//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

// MARK: - GroupCallViewController

// TODO: Eventually add 1:1 call support to this view
// and replace CallViewController
class GroupCallViewController: UIViewController {

    // MARK: Properties

    private let call: SignalCall
    private let groupCall: GroupCall
    private let ringRtcCall: SignalRingRTC.GroupCall
    private lazy var callControlsConfirmationToastManager = CallControlsConfirmationToastManager(
        presentingContainerView: callControlsConfirmationToastContainerView
    )
    private lazy var callControls = CallControls(
        call: call,
        callService: callService,
        confirmationToastManager: callControlsConfirmationToastManager,
        delegate: self
    )
    private lazy var callControlsConfirmationToastContainerView = UIView()
    private var callService: CallService { AppEnvironment.shared.callService }
    private var incomingCallControls: IncomingCallControls?
    private lazy var callHeader = CallHeader(groupCall: groupCall, delegate: self)
    private lazy var notificationView = GroupCallNotificationView(groupCall: groupCall)

    /// A UIStackView which allows taps on its subviews, but passes taps outside of those or in explicitly ignored views through to the parent.
    private class PassthroughStackView: UIStackView {
        var ignoredViews: WeakArray<UIView> = []

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // super.hitTest will return the deepest view hit, so if it's
            // just `self`, the highest view, that means a subview wasn't hit.
            let hitView = super.hitTest(point, with: event)
            if let hitView, hitView == self || ignoredViews.contains(hitView) {
                return nil
            }
            return hitView
        }
    }

    private let bottomVStack = PassthroughStackView()
    private let videoOverflowContainer = UIView()
    private let raisedHandsToastContainer = UIView()
    private lazy var raisedHandsToast = RaisedHandsToast(call: self.groupCall)

    private lazy var videoGrid: GroupCallVideoGrid = {
        let result = GroupCallVideoGrid(call: call, groupCall: groupCall)
        result.memberViewErrorPresenter = self
        return result
    }()

    private lazy var videoOverflow: GroupCallVideoOverflow = {
        let result = GroupCallVideoOverflow(call: call, groupCall: groupCall, delegate: self)
        result.memberViewErrorPresenter = self
        return result
    }()

    private lazy var speakerView: CallMemberView = {
        let result = CallMemberView(type: .remoteInGroup(.speaker))
        result.errorPresenter = self
        return result
    }()

    private lazy var localMemberView: CallMemberView = {
        let result = CallMemberView(type: .local)
        result.errorPresenter = self
        result.animatableLocalMemberViewDelegate = self
        return result
    }()

    private var didUserEverSwipeToSpeakerView = true
    private var didUserEverSwipeToScreenShare = true
    private let swipeToastView = GroupCallSwipeToastView()

    private let speakerPage = UIView()

    private let scrollView = UIScrollView()

    private let incomingReactionsView = IncomingReactionsView()

    private var isCallMinimized = false {
        didSet {
            speakerView.isCallMinimized = isCallMinimized
            scheduleControlTimeoutIfNecessary()
        }
    }

    private var isAutoScrollingToScreenShare = false
    private var isAnyRemoteDeviceScreenSharing = false {
        didSet {
            guard oldValue != isAnyRemoteDeviceScreenSharing else { return }

            // Scroll to speaker view when presenting begins.
            if isAnyRemoteDeviceScreenSharing {
                isAutoScrollingToScreenShare = true
                scrollView.setContentOffset(CGPoint(x: 0, y: speakerPage.frame.origin.y), animated: true)
            }
        }
    }

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTouchRootView))
    private lazy var bottomVStackTopConstraint = self.bottomVStack.autoPinEdge(.bottom, to: .top, of: self.view)
    private lazy var videoOverflowTrailingConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .trailing)

    private enum CallControlsDisplayState {
        /// "Overflow" refers to the "..." menu that shows reactions & "Raise Hand".
        case callControlsAndOverflow
        case callControlsOnly
        case none
    }

    private var callControlsDisplayState: CallControlsDisplayState = .callControlsOnly {
        didSet {
            updateCallUI()
            scheduleControlTimeoutIfNecessary()
        }
    }

    private var hasUnresolvedSafetyNumberMismatch = false
    private var hasDismissed = false

    private var membersAtJoin: Set<SignalServiceAddress>?

    private static let keyValueStore = SDSKeyValueStore(collection: "GroupCallViewController")
    private static let didUserSwipeToSpeakerViewKey = "didUserSwipeToSpeakerView"
    private static let didUserSwipeToScreenShareKey = "didUserSwipeToScreenShare"

    /// When the local member view (which is displayed picture-in-picture) is
    /// tapped, it expands. If the frame is expanded, its enlarged frame is
    /// stored here. If the pip is not in the expanded state, this value is nil.
    private var expandedPipFrame: CGRect?

    /// Whether the local member view pip has an animation currently in progress.
    private var isPipAnimationInProgress = false

    /// Whether a relayout needs to occur after the pip animation completes.
    /// This is true when we suspended an attempted relayout triggered during
    /// the pip animation.
    private var shouldRelayoutAfterPipAnimationCompletes = false
    private var postAnimationUpdateMemberViewFramesSize: CGSize?
    private var postAnimationUpdateMemberViewFramesControlsAreHidden: Bool?

    private lazy var reactionsBurstView: ReactionsBurstView = {
        ReactionsBurstView(burstAligner: self.incomingReactionsView)
    }()
    private lazy var reactionsSink: ReactionsSink = {
        ReactionsSink(reactionReceivers: [
            self.incomingReactionsView,
            self.reactionsBurstView
        ])
    }()
    private lazy var callControlsOverflowView: CallControlsOverflowView = {
        return CallControlsOverflowView(
            call: self.call,
            reactionSender: self.ringRtcCall,
            reactionsSink: self.reactionsSink,
            raiseHandSender: self.ringRtcCall,
            emojiPickerSheetPresenter: self,
            callControlsOverflowPresenter: self
        )
    }()

    init(call: SignalCall, groupCall: GroupCall) {
        // TODO: Eventually unify UI for group and individual calls

        self.call = call
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall

        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    static func presentLobby(thread: TSGroupThread, videoMuted: Bool = false) {
        self._presentLobby { viewController in
            let result = await self._prepareLobby(from: viewController, shouldAskForCameraPermission: !videoMuted) {
                let callService = AppEnvironment.shared.callService!
                return callService.buildAndConnectGroupCall(for: thread, isVideoMuted: videoMuted)
            }
            await databaseStorage.awaitableWrite { tx in
                // Dismiss the group call tooltip
                self.preferences.setWasGroupCallTooltipShown(tx: tx)
            }
            return result
        }
    }

    static func presentLobby(for callLink: CallLink) {
        guard RemoteConfig.callLinkJoin else {
            return
        }
        self._presentLobby { viewController in
            do {
                return try await self._prepareLobby(from: viewController, shouldAskForCameraPermission: true) {
                    let callService = AppEnvironment.shared.callService!
                    return try await callService.buildAndConnectCallLinkCall(callLink: callLink)
                }
            } catch {
                owsFail("[CallLink] TODO: Couldn't buildAndConnectCallLinkCall \(error)")
            }
        }
    }

    private static func _presentLobby(
        prepareLobby: @escaping @MainActor (UIViewController) async -> (() -> Void)?
    ) {
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFail("Can't start a call if there's no view controller")
        }

        // [CallLink] TODO: Check if `canCancel` should be true.
        // Gotchas:
        // - Incoming group calls that are ringing.
        // - Disconnecting calls that the user cancels.
        ModalActivityIndicatorViewController.present(
            fromViewController: frontmostViewController,
            canCancel: false,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                let presentLobby = await prepareLobby(frontmostViewController)
                modal.dismissIfNotCanceled(completionIfNotCanceled: presentLobby ?? {})
            }
        )
    }

    private static func _prepareLobby(
        from viewController: UIViewController,
        shouldAskForCameraPermission: Bool,
        buildAndStartConnecting: () async throws -> (SignalCall, GroupCall)?
    ) async rethrows -> (() -> Void)? {
        guard await CallStarter.prepareToStartCall(from: viewController, shouldAskForCameraPermission: shouldAskForCameraPermission) else {
            return nil
        }

        guard let (call, groupCall) = try await buildAndStartConnecting() else {
            owsFailDebug("Can't show lobby if the call can't start")
            return nil
        }

        let vc = GroupCallViewController(call: call, groupCall: groupCall)
        return {
            vc.modalTransitionStyle = .crossDissolve
            WindowManager.shared.startCall(viewController: vc)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func loadView() {
        view = UIView()
        view.clipsToBounds = true

        view.backgroundColor = .ows_black

        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        scrollView.autoPinEdgesToSuperviewEdges()

        view.addSubview(callHeader)
        callHeader.autoPinWidthToSuperview()
        callHeader.autoPinEdge(toSuperviewEdge: .top)

        view.addSubview(notificationView)
        notificationView.autoPinEdgesToSuperviewEdges()

        view.addSubview(callControls)
        callControls.autoPinWidthToSuperview()
        callControls.autoPinEdge(toSuperviewEdge: .bottom)

        view.addSubview(self.bottomVStack)
        self.bottomVStack.autoPinWidthToSuperview()
        self.bottomVStack.axis = .vertical
        self.bottomVStack.preservesSuperviewLayoutMargins = true

        videoOverflowContainer.addSubview(self.videoOverflow)
        self.bottomVStack.addArrangedSubview(videoOverflowContainer)
        self.bottomVStack.ignoredViews.append(videoOverflowContainer)
        self.videoOverflow.autoPinHeightToSuperview()
        self.videoOverflow.autoPinEdge(toSuperviewEdge: .leading)

        raisedHandsToastContainer.layoutMargins = .init(margin: 0)
        raisedHandsToastContainer.preservesSuperviewLayoutMargins = true
        raisedHandsToastContainer.addSubview(raisedHandsToast)
        raisedHandsToastContainer.isHiddenInStackView = true
        self.bottomVStack.insertArrangedSubview(raisedHandsToastContainer, at: 0)
        self.bottomVStack.ignoredViews.append(raisedHandsToastContainer)
        raisedHandsToast.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        raisedHandsToast.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        raisedHandsToast.horizontalPinConstraint = raisedHandsToast.autoPinEdge(toSuperviewMargin: .leading)
        raisedHandsToast.delegate = self

        scrollView.addSubview(videoGrid)
        scrollView.addSubview(speakerPage)

        view.addSubview(incomingReactionsView)
        incomingReactionsView.autoPinEdge(.leading, to: .leading, of: view, withOffset: 22)
        incomingReactionsView.autoPinEdge(.bottom, to: .top, of: self.bottomVStack, withOffset: -16)
        incomingReactionsView.widthAnchor.constraint(equalToConstant: IncomingReactionsView.Constants.viewWidth).isActive = true
        incomingReactionsView.heightAnchor.constraint(equalToConstant: IncomingReactionsView.viewHeight).isActive = true

        scrollView.addSubview(swipeToastView)
        swipeToastView.autoPinEdge(.bottom, to: .bottom, of: videoGrid, withOffset: -22)
        swipeToastView.autoHCenterInSuperview()
        swipeToastView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        swipeToastView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        view.addSubview(callControlsConfirmationToastContainerView)
        callControlsConfirmationToastContainerView.autoPinEdge(.bottom, to: .top, of: callControls, withOffset: -30)
        callControlsConfirmationToastContainerView.autoHCenterInSuperview()

        view.addSubview(callControlsOverflowView)
        if UIDevice.current.isIPad {
            callControlsOverflowView.centerXAnchor.constraint(equalTo: callControls.centerXAnchor).isActive = true
        } else {
            callControlsOverflowView.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -12)
        }
        callControlsOverflowView.autoPinEdge(.bottom, to: .top, of: callControls, withOffset: -12)

        view.addSubview(reactionsBurstView)
        reactionsBurstView.autoPinEdgesToSuperviewEdges()

        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        SDSDatabaseStorage.shared.asyncRead { readTx in
            self.didUserEverSwipeToSpeakerView = Self.keyValueStore.getBool(
                Self.didUserSwipeToSpeakerViewKey,
                defaultValue: false,
                transaction: readTx
            )
            self.didUserEverSwipeToScreenShare = Self.keyValueStore.getBool(
                Self.didUserSwipeToScreenShareKey,
                defaultValue: false,
                transaction: readTx
            )
        } completion: {
            self.updateSwipeToastView()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let wasOnSpeakerPage = scrollView.contentOffset.y >= view.height

        coordinator.animate(alongsideTransition: { _ in
            self.updateCallUI(size: size)
            self.videoGrid.reloadData()
            self.videoOverflow.reloadData()
            self.scrollView.contentOffset = wasOnSpeakerPage ? CGPoint(x: 0, y: size.height) : .zero
        }, completion: nil)
    }

    private var hasAppeared = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !hasAppeared else { return }
        hasAppeared = true

        callService.sendInitialPhoneOrientationNotification()

        if let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false) {
            view.superview?.insertSubview(splitViewSnapshot, belowSubview: view)
            splitViewSnapshot.autoPinEdgesToSuperviewEdges()

            view.transform = .scale(1.5)
            view.alpha = 0

            UIView.animate(withDuration: 0.2, animations: {
                self.view.alpha = 1
                self.view.transform = .identity
            }) { _ in
                splitViewSnapshot.removeFromSuperview()
            }
        }
    }

    private var isReadyToUpdateUI = false
    private var didAddObserver = false
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        if !didAddObserver {
            groupCall.addObserver(self)
            didAddObserver = true
        }

        isReadyToUpdateUI = true
        updateCallUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if hasUnresolvedSafetyNumberMismatch && CurrentAppContext().isAppForegroundAndActive() {
            // If we're not active yet, this will be handled by the `didBecomeActive` callback.
            resolveSafetyNumberMismatch()
        }
    }

    @objc
    private func didBecomeActive() {
        if hasUnresolvedSafetyNumberMismatch {
            resolveSafetyNumberMismatch()
        }
    }

    // MARK: Call members

    private func updateScrollViewFrames(size: CGSize? = nil, controlsAreHidden: Bool) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        if ringRtcCall.remoteDeviceStates.count < 2 || ringRtcCall.localDeviceState.joinState != .joined {
            videoGrid.frame = .zero
            videoGrid.isHidden = true
            speakerPage.frame = CGRect(
                x: 0,
                y: 0,
                width: size.width,
                height: size.height
            )
            scrollView.contentSize = size
            scrollView.contentOffset = .zero
            scrollView.isScrollEnabled = false
        } else {
            let wasVideoGridHidden = videoGrid.isHidden
            let controlsHeight = controlsAreHidden ? 16 : callControls.height
            let hasOverflowMembersInGridView = videoGrid.maxItems < ringRtcCall.remoteDeviceStates.count
            let overflowGridHeight = hasOverflowMembersInGridView ? videoOverflow.height + 27 : 0

            scrollView.isScrollEnabled = true
            videoGrid.isHidden = false
            videoGrid.frame = CGRect(
                x: 0,
                y: view.safeAreaInsets.top,
                width: size.width,
                height: size.height - view.safeAreaInsets.top - controlsHeight - overflowGridHeight
            )
            speakerPage.frame = CGRect(
                x: 0,
                y: size.height,
                width: size.width,
                height: size.height
            )
            scrollView.contentSize = CGSize(width: size.width, height: size.height * 2)

            if wasVideoGridHidden {
                scrollView.contentOffset = .zero
            }
        }
    }

    func updateVideoOverflowTrailingConstraint() {
        var trailingConstraintConstant = -(GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.inherentPipSize.aspectRatio + 4)
        if view.width + trailingConstraintConstant > videoOverflow.contentSize.width {
            trailingConstraintConstant += 16
        }
        videoOverflowTrailingConstraint.constant = trailingConstraintConstant
        view.layoutIfNeeded()
    }

    private func updateBottomVStackItems() {
        guard FeatureFlags.callRaiseHandToastSupport else {
            self.raisedHandsToastContainer.isHidden = true
            return
        }

        self.raisedHandsToastContainer.isHiddenInStackView = self.raisedHandsToast.raisedHands.isEmpty

        func moveToTopIfNotAlready(_ view: UIView) {
            guard self.bottomVStack.arrangedSubviews.last == view else { return }
            self.bottomVStack.removeArrangedSubview(view)
            self.bottomVStack.insertArrangedSubview(view, at: 0)
        }

        let hasOverflowMembers = !self.videoOverflow.overflowedRemoteDeviceStates.isEmpty

        if hasOverflowMembers {
            moveToTopIfNotAlready(self.raisedHandsToastContainer)
        } else {
            moveToTopIfNotAlready(self.videoOverflowContainer)
        }

        let isOnGridView = scrollView.contentOffset.y == 0
        if
            hasOverflowMembers,
            isOnGridView
        {
            self.bottomVStack.spacing = 24
        } else {
            self.bottomVStack.spacing = 12
        }
    }

    private func updateMemberViewFrames(size: CGSize? = nil, controlsAreHidden: Bool) {
        guard !isPipAnimationInProgress else {
            // Wait for the pip to reach its new size before re-laying out.
            // Otherwise the pip snaps back to its size at the start of the
            // animation, effectively undoing it. When the animation is
            // complete, we'll call `updateMemberViewFrames`.
            self.shouldRelayoutAfterPipAnimationCompletes = true
            self.postAnimationUpdateMemberViewFramesSize = size
            self.postAnimationUpdateMemberViewFramesControlsAreHidden = controlsAreHidden
            return
        }

        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        let yMax = (controlsAreHidden ? size.height - 16 : callControls.frame.minY) - 16

        bottomVStackTopConstraint.constant = yMax

        updateVideoOverflowTrailingConstraint()

        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            view.removeFromSuperview()
        }

        speakerView.applyChangesToCallMemberViewAndVideoView { view in
            view.removeFromSuperview()
        }
        switch ringRtcCall.localDeviceState.joinState {
        case .joined:
            if ringRtcCall.remoteDeviceStates.count > 0 {
                speakerView.applyChangesToCallMemberViewAndVideoView { view in
                    speakerPage.addSubview(view)
                    view.autoPinEdgesToSuperviewEdges()
                }

                localMemberView.applyChangesToCallMemberViewAndVideoView { aView in
                    view.insertSubview(aView, belowSubview: callControlsConfirmationToastContainerView)
                }

                let pipSize = CallMemberView.pipSize(
                    expandedPipFrame: self.expandedPipFrame,
                    remoteDeviceCount: ringRtcCall.remoteDeviceStates.count
                )

                let y: CGFloat
                if nil != expandedPipFrame {
                    // Necessary because when the pip is expanded, the
                    // pip height will not follow along with that of
                    // the video overflow, which is tiny.
                    y = yMax - pipSize.height
                } else {
                    let overflowY = videoOverflow.convert(videoOverflow.bounds.origin, to: self.view).y
                    let overflowPipHeightDifference = pipSize.height - videoOverflow.height
                    y = overflowY - overflowPipHeightDifference
                }
                localMemberView.applyChangesToCallMemberViewAndVideoView { view in
                    view.frame = CGRect(
                        x: size.width - pipSize.width - 16,
                        y: y,
                        width: pipSize.width,
                        height: pipSize.height
                    )
                }
                flipCameraTooltipManager.presentTooltipIfNecessary(
                    fromView: self.view,
                    widthReferenceView: self.view,
                    tailReferenceView: localMemberView,
                    tailDirection: .down,
                    isVideoMuted: call.isOutgoingVideoMuted
                )
            } else {
                localMemberView.applyChangesToCallMemberViewAndVideoView { view in
                    speakerPage.addSubview(view)
                    view.frame = CGRect(origin: .zero, size: size)
                }
            }
        case .notJoined, .joining, .pending:
            localMemberView.applyChangesToCallMemberViewAndVideoView { view in
                speakerPage.addSubview(view)
                view.frame = CGRect(origin: .zero, size: size)
            }
        }
    }

    // MARK: Other UI

    func updateSwipeToastView() {
        let isSpeakerViewAvailable = ringRtcCall.remoteDeviceStates.count >= 2 && ringRtcCall.localDeviceState.joinState == .joined
        guard isSpeakerViewAvailable else {
            swipeToastView.isHidden = true
            return
        }

        if isAnyRemoteDeviceScreenSharing {
            if didUserEverSwipeToScreenShare {
                swipeToastView.isHidden = true
                return
            }
        } else if didUserEverSwipeToSpeakerView {
            swipeToastView.isHidden = true
            return
        }

        swipeToastView.alpha = 1.0 - (scrollView.contentOffset.y / view.height)
        swipeToastView.text = isAnyRemoteDeviceScreenSharing
            ? OWSLocalizedString(
                "GROUP_CALL_SCREEN_SHARE_TOAST",
                comment: "Toast view text informing user about swiping to screen share"
            )
            : OWSLocalizedString(
                "GROUP_CALL_SPEAKER_VIEW_TOAST",
                comment: "Toast view text informing user about swiping to speaker view"
            )

        if scrollView.contentOffset.y >= view.height {
            swipeToastView.isHidden = true

            if isAnyRemoteDeviceScreenSharing {
                if !isAutoScrollingToScreenShare {
                    didUserEverSwipeToScreenShare = true
                    SDSDatabaseStorage.shared.asyncWrite { writeTx in
                        Self.keyValueStore.setBool(true, key: Self.didUserSwipeToScreenShareKey, transaction: writeTx)
                    }
                }
            } else {
                didUserEverSwipeToSpeakerView = true
                SDSDatabaseStorage.shared.asyncWrite { writeTx in
                    Self.keyValueStore.setBool(true, key: Self.didUserSwipeToSpeakerViewKey, transaction: writeTx)
                }
            }

        } else if swipeToastView.isHidden {
            swipeToastView.alpha = 0
            swipeToastView.isHidden = false
            UIView.animate(withDuration: 0.2, delay: 3.0, options: []) {
                self.swipeToastView.alpha = 1
            }
        }
    }

    private var flipCameraTooltipManager = FlipCameraTooltipManager(db: DependenciesBridge.shared.db)

    private func updateCallUI(
        size: CGSize? = nil,
        shouldAnimateViewFrames: Bool = false
    ) {
        owsAssertDebug(self.isReadyToUpdateUI)

        let localDevice = ringRtcCall.localDeviceState

        let isFullScreen = localDevice.joinState != .joined || ringRtcCall.remoteDeviceStates.isEmpty
        localMemberView.configure(
            call: call,
            isFullScreen: isFullScreen
        )

        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            // In the context of `isCallInPip`, the "pip" refers to when the entire call is in a pip
            // (ie, minimized in the app). This is not to be confused with the local member view pip
            // (ie, when the call is full screen and the local user is displayed in a pip).
            // The following line disallows having a [local member] pip within a [call] pip.
            view.isHidden = WindowManager.shared.isCallInPip
        }

        if let speakerState = ringRtcCall.remoteDeviceStates.sortedBySpeakerTime.first {
            speakerView.configure(
                call: call,
                remoteGroupMemberDeviceState: speakerState
            )
        } else {
            speakerView.clearConfiguration()
        }

        guard !isCallMinimized else { return }

        if
            case .groupThread(let groupThreadCall) = groupCall.concreteType,
            groupThreadCall.groupCallRingState.isIncomingRing
        {
            callControls.isHidden = true
            createIncomingCallControlsIfNeeded().isHidden = false
            // These views aren't visible at this point, but we need them to be configured anyway.
            updateMemberViewFrames(size: size, controlsAreHidden: true)
            updateScrollViewFrames(size: size, controlsAreHidden: true)
            return
        }

        if let incomingCallControls, !incomingCallControls.isHidden {
            // We were showing the incoming call controls, but now we don't want to.
            // To make sure all views transition properly, pretend we were showing the regular controls all along.
            callControls.isHidden = false
            incomingCallControls.isHidden = true
        }

        let callControlsAreHidden = callControls.isHidden && callHeader.isHidden
        let callControlsOverflowContentIsHidden = self.callControlsOverflowView.isHidden
        if !callControlsAreHidden && !callControlsOverflowContentIsHidden {
            self.callControlDisplayStateDidChange(
                oldState: .callControlsAndOverflow,
                newState: self.callControlsDisplayState,
                size: size,
                shouldAnimateViewFrames: shouldAnimateViewFrames
            )
        } else if !callControlsAreHidden {
            self.callControlDisplayStateDidChange(
                oldState: .callControlsOnly,
                newState: self.callControlsDisplayState,
                size: size,
                shouldAnimateViewFrames: shouldAnimateViewFrames
            )
        } else if !callControlsOverflowContentIsHidden {
            owsFailDebug("Call Controls Overflow content should never be visible while Call Controls are hidden. Desired new state: \(self.callControlsDisplayState).")
            recoverFromOverflowOnlyCallControlsDisplayState(
                newState: self.callControlsDisplayState,
                size: size
            )
        } else {
            self.callControlDisplayStateDidChange(
                oldState: .none,
                newState: self.callControlsDisplayState,
                size: size,
                shouldAnimateViewFrames: shouldAnimateViewFrames
            )
        }

        updateSwipeToastView()
    }

    // Theoretically, we should never show the call controls overflow _only_, without call controls
    // accompanying it. However, this does somehow happen. As a quick fix, we'll bring the UI back
    // to a sane state via this method. But a deeper investigation as to how this state is reached
    // in the first place is warranted.
    private func recoverFromOverflowOnlyCallControlsDisplayState(
        newState: CallControlsDisplayState,
        size: CGSize?
    ) {
        switch newState {
        case .callControlsAndOverflow:
            animateCallControls(
                hideCallControls: false,
                size: size
            )
        case .callControlsOnly:
            animateCallControls(
                hideCallControls: false,
                size: size
            )
            self.callControlsOverflowView.animateOut()
        case .none:
            self.callControlsOverflowView.animateOut()
        }
    }

    private func callControlDisplayStateDidChange(
        oldState: CallControlsDisplayState,
        newState: CallControlsDisplayState,
        size: CGSize?,
        shouldAnimateViewFrames: Bool
    ) {
        func updateFrames(controlsAreHidden: Bool) {
            let raisedHandsToastWasAlreadyHidden = self.raisedHandsToastContainer.isHidden

            let action: () -> Void = {
                self.updateBottomVStackItems()
                self.updateMemberViewFrames(size: size, controlsAreHidden: controlsAreHidden)
                self.updateScrollViewFrames(size: size, controlsAreHidden: controlsAreHidden)
            }
            let completion: () -> Void = {
                if
                    self.raisedHandsToast.raisedHands.isEmpty,
                    !raisedHandsToastWasAlreadyHidden
                {
                    self.raisedHandsToast.wasHidden()
                }
            }

            if shouldAnimateViewFrames {
                let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
                animator.addAnimations(action)
                animator.addCompletion { _ in
                    completion()
                }
                animator.startAnimation()
            } else {
                action()
                completion()
            }
        }

        switch oldState {
        case .callControlsAndOverflow:
            switch newState {
            case .callControlsAndOverflow:
                updateFrames(controlsAreHidden: false)
            case .callControlsOnly:
                self.callControlsOverflowView.animateOut()
                updateFrames(controlsAreHidden: false)
            case .none:
                // This can happen if you tap the root view fast enough in succession.
                animateCallControls(
                    hideCallControls: true,
                    size: size
                )
                self.callControlsOverflowView.animateOut()
            }
        case .callControlsOnly:
            switch newState {
            case .callControlsAndOverflow:
                self.callControlsOverflowView.animateIn()
                updateFrames(controlsAreHidden: false)
            case .callControlsOnly:
                updateFrames(controlsAreHidden: false)
            case .none:
                animateCallControls(
                    hideCallControls: true,
                    size: size
                )
            }
        case .none:
            switch newState {
            case .callControlsAndOverflow:
                owsFailDebug("Impossible callControlsDisplayState transition")
                // But if you must...
                animateCallControls(
                    hideCallControls: false,
                    size: size
                )
                self.callControlsOverflowView.animateIn()
            case .callControlsOnly:
                animateCallControls(
                    hideCallControls: false,
                    size: size
                )
            case .none:
                updateFrames(controlsAreHidden: true)
            }
        }
    }

    private func animateCallControls(
        hideCallControls: Bool,
        size: CGSize?
    ) {
        callControls.isHidden = false
        callHeader.isHidden = false
        UIView.animate(withDuration: 0.15, animations: {
            self.callControls.alpha = hideCallControls ? 0 : 1
            self.callHeader.alpha = hideCallControls ? 0 : 1

            self.updateBottomVStackItems()
            self.updateMemberViewFrames(size: size, controlsAreHidden: hideCallControls)
            self.updateScrollViewFrames(size: size, controlsAreHidden: hideCallControls)
            self.view.layoutIfNeeded()
        }) { _ in
            self.callControls.isHidden = hideCallControls
            self.callHeader.isHidden = hideCallControls
            // If a hand is raised during this animation, the toast will be
            // positioned wrong unless this is called again in the completion.
            self.updateBottomVStackItems()

            if self.raisedHandsToast.raisedHands.isEmpty {
                self.raisedHandsToast.wasHidden()
            }
        }
    }

    private func dismissCall(shouldHangUp: Bool = true) {
        if shouldHangUp {
            callService.callUIAdapter.localHangupCall(call)
        }
        didHangupCall()
    }

    private func didHangupCall() {
        guard !hasDismissed else {
            return
        }
        hasDismissed = true

        self.callControlsDisplayState = .callControlsOnly

        guard
            let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false),
            view.superview?.insertSubview(splitViewSnapshot, belowSubview: view) != nil
        else {
            // This can happen if we're in the background when the call is dismissed (say, from CallKit).
            WindowManager.shared.endCall(viewController: self)
            return
        }

        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        UIView.animate(withDuration: 0.2, animations: {
            self.view.alpha = 0
        }) { _ in
            splitViewSnapshot.removeFromSuperview()
            WindowManager.shared.endCall(viewController: self)
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    // MARK: - Call controls timeout

    @objc
    private func didTouchRootView(sender: UIGestureRecognizer) {
        if callControlsMustBeVisible {
            return
        }
        switch self.callControlsDisplayState {
        case .callControlsAndOverflow, .none:
            self.callControlsDisplayState = .callControlsOnly
        case .callControlsOnly:
            self.callControlsDisplayState = .none
        }
    }

    private var callControlsMustBeVisible: Bool {
        return ringRtcCall.remoteDeviceStates.isEmpty
    }

    private var controlTimeoutTimer: Timer?
    private func scheduleControlTimeoutIfNecessary() {
        let shouldAutomaticallyHideCallControls: Bool = {
            switch self.callControlsDisplayState {
            case .callControlsAndOverflow, .none:
                return false
            case .callControlsOnly:
                break
            }

            if callControlsMustBeVisible {
                return false
            }

            if isCallMinimized {
                return false
            }

            return true
        }()

        guard shouldAutomaticallyHideCallControls else {
            controlTimeoutTimer?.invalidate()
            controlTimeoutTimer = nil
            return
        }

        guard controlTimeoutTimer == nil else { return }
        controlTimeoutTimer = .scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.timeoutControls()
        }
    }

    private func timeoutControls() {
        self.controlTimeoutTimer = nil
        self.callControlsDisplayState = .none
    }

    private func showCallControlsIfTheyMustBeVisible() {
        if callControlsMustBeVisible {
            showCallControlsIfHidden()
        }
    }

    private func showCallControlsIfHidden() {
        switch self.callControlsDisplayState {
        case .callControlsAndOverflow, .callControlsOnly:
            break
        case .none:
            self.callControlsDisplayState = .callControlsOnly
        }
    }

    // MARK: - Ringing/Incoming Call Controls

    private func createIncomingCallControlsIfNeeded() -> IncomingCallControls {
        if let incomingCallControls {
            return incomingCallControls
        }
        let incomingCallControls = IncomingCallControls(
            isVideoCall: true,
            didDeclineCall: { [unowned self] in self.dismissCall() },
            didAcceptCall: { [unowned self] hasVideo in self.acceptRingingIncomingCall(hasVideo: hasVideo) }
        )
        self.view.addSubview(incomingCallControls)
        incomingCallControls.autoPinWidthToSuperview()
        incomingCallControls.autoPinEdge(toSuperviewEdge: .bottom)
        self.incomingCallControls = incomingCallControls
        return incomingCallControls
    }

    private func acceptRingingIncomingCall(hasVideo: Bool) {
        // Explicitly unmute video in order to request permissions as needed.
        // (Audio is unmuted as part of the call UI adapter.)

        callService.updateIsLocalVideoMuted(isLocalVideoMuted: !hasVideo)
        // When turning off video, default speakerphone to on.
        if !hasVideo, !callService.audioService.hasExternalInputs {
            callService.audioService.requestSpeakerphone(call: call, isEnabled: true)
        }

        callService.callUIAdapter.answerCall(call)
    }
}

// MARK: CallViewControllerWindowReference

extension GroupCallViewController: CallViewControllerWindowReference {
    var localVideoViewReference: CallMemberView { localMemberView }
    var remoteVideoViewReference: CallMemberView { speakerView }

    var remoteVideoAddress: SignalServiceAddress {
        guard let firstMember = ringRtcCall.remoteDeviceStates.sortedByAddedTime.first else {
            return DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress
        }
        return firstMember.address
    }

    public func returnFromPip(pipWindow: UIWindow) {
        // The call "pip" uses our remote and local video views since only
        // one `AVCaptureVideoPreviewLayer` per capture session is supported.
        // We need to re-add them when we return to this view.
        guard speakerView.superview != speakerPage && localMemberView.superview != view else {
            return owsFailDebug("unexpectedly returned to call while we own the video views")
        }

        guard let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot rootViewController")
        }

        guard let pipSnapshot = pipWindow.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot pip")
        }

        isCallMinimized = false

        showCallControlsIfHidden()

        animateReturnFromPip(pipSnapshot: pipSnapshot, pipFrame: pipWindow.frame, splitViewSnapshot: splitViewSnapshot)
    }

    func willMoveToPip(pipWindow: UIWindow) {
        flipCameraTooltipManager.dismissTooltip()
        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            view.isHidden = true
        }
    }

    private func animateReturnFromPip(pipSnapshot: UIView, pipFrame: CGRect, splitViewSnapshot: UIView) {
        guard let window = view.window else { return owsFailDebug("missing window") }
        view.superview?.insertSubview(splitViewSnapshot, belowSubview: view)
        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        let originalContentOffset = scrollView.contentOffset

        view.frame = pipFrame
        view.addSubview(pipSnapshot)
        pipSnapshot.autoPinEdgesToSuperviewEdges()

        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            pipSnapshot.alpha = 0
            self.view.frame = window.frame
            self.updateCallUI()
            self.videoGrid.reloadData()
            self.scrollView.contentOffset = originalContentOffset
            self.view.layoutIfNeeded()
        }) { _ in
            splitViewSnapshot.removeFromSuperview()
            pipSnapshot.removeFromSuperview()

            if self.hasUnresolvedSafetyNumberMismatch {
                self.resolveSafetyNumberMismatch()
            }
        }
    }

    private func safetyNumberMismatchAddresses(untrustedThreshold: Date?) -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            let addressesToCheck: [SignalServiceAddress]
            if
                case .groupThread(let groupThreadCall) = groupCall.concreteType,
                ringRtcCall.localDeviceState.joinState == .notJoined
            {
                // If we haven't joined the call yet, we want to alert for all members of the group
                addressesToCheck = groupThreadCall.groupThread.recipientAddresses(with: transaction)
            } else {
                // If we are in the call, we only care about safety numbers for the active call participants
                addressesToCheck = ringRtcCall.remoteDeviceStates.map { $0.value.address }
            }

            let identityManager = DependenciesBridge.shared.identityManager
            return addressesToCheck.filter { memberAddress in
                identityManager.untrustedIdentityForSending(
                    to: memberAddress,
                    untrustedThreshold: untrustedThreshold,
                    tx: transaction.asV2Read
                ) != nil
            }
        }
    }

    private func groupCallThreadForSafetyNumberMismatch() -> GroupThreadCall {
        switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            return groupThreadCall
        case .callLink:
            owsFail("[CallLink] TODO: Support Safety Number mismatches.")
        }
    }

    fileprivate func resolveSafetyNumberMismatch() {
        let resendMediaKeysAndResetMismatch = { [unowned self] in
            self.ringRtcCall.resendMediaKeys()
            self.hasUnresolvedSafetyNumberMismatch = false
        }

        if !isCallMinimized, CurrentAppContext().isAppForegroundAndActive() {
            presentSafetyNumberChangeSheetIfNecessary { [weak self] success in
                guard let self = self else { return }
                if success {
                    resendMediaKeysAndResetMismatch()
                } else {
                    self.dismissCall()
                }
            }
        } else {
            let unresolvedAddresses = safetyNumberMismatchAddresses(untrustedThreshold: nil)
            guard !unresolvedAddresses.isEmpty else {
                // Spurious warning, maybe from delayed callbacks.
                resendMediaKeysAndResetMismatch()
                return
            }

            // If a problematic member was present at join, leaves, and then joins again,
            // we'll still treat them as having been there "since join", but that's okay.
            // It's not worth trying to track this more precisely.
            let atLeastOneUnresolvedPresentAtJoin = unresolvedAddresses.contains { membersAtJoin?.contains($0) ?? false }
            Self.notificationPresenterImpl.notifyForGroupCallSafetyNumberChange(
                inThread: self.groupCallThreadForSafetyNumberMismatch().groupThread,
                presentAtJoin: atLeastOneUnresolvedPresentAtJoin
            )
        }
    }

    fileprivate func presentSafetyNumberChangeSheetIfNecessary(untrustedThreshold: Date? = nil, completion: @escaping (Bool) -> Void) {
        let localDeviceHasNotJoined = ringRtcCall.localDeviceState.joinState == .notJoined
        let newUntrustedThreshold = Date()
        let addressesToAlert = safetyNumberMismatchAddresses(untrustedThreshold: untrustedThreshold)

        // There are no unverified addresses that we're currently concerned about. No need to show a sheet
        guard !addressesToAlert.isEmpty else { return completion(true) }

        if let existingSheet = presentedViewController as? SafetyNumberConfirmationSheet {
            // The set of untrusted addresses may have changed.
            // It's a bit clunky, but we'll just dismiss the existing sheet before putting up a new one.
            existingSheet.dismiss(animated: false)
        }

        let continueCallString = OWSLocalizedString("GROUP_CALL_CONTINUE_BUTTON", comment: "Button to continue an ongoing group call")
        let leaveCallString = OWSLocalizedString("GROUP_CALL_LEAVE_BUTTON", comment: "Button to leave a group call")
        let cancelString = CommonStrings.cancelButton

        let approveText: String
        let denyText: String
        if localDeviceHasNotJoined {
            approveText = CallControls.joinButtonLabel(for: call)
            denyText = cancelString
        } else {
            approveText = continueCallString
            denyText = leaveCallString
        }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: addressesToAlert,
            confirmationText: approveText,
            cancelText: denyText,
            theme: .translucentDark
        ) { [weak self] didApprove in
            if let self, didApprove {
                self.presentSafetyNumberChangeSheetIfNecessary(untrustedThreshold: newUntrustedThreshold, completion: completion)
            } else {
                completion(false)
            }
        }
        sheet.allowsDismissal = localDeviceHasNotJoined
        present(sheet, animated: true, completion: nil)
    }
}

// MARK: CallObserver

extension GroupCallViewController: GroupCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsAssert(self.groupCall === call)

        updateCallUI()

        switch ringRtcCall.localDeviceState.joinState {
        case .joined:
            if membersAtJoin == nil {
                membersAtJoin = Set(ringRtcCall.remoteDeviceStates.lazy.map { $0.value.address })
            }
        case .pending, .joining, .notJoined:
            membersAtJoin = nil
        }
    }

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsAssert(self.groupCall === call)

        isAnyRemoteDeviceScreenSharing = ringRtcCall.remoteDeviceStates.values.first { $0.sharingScreen == true } != nil

        showCallControlsIfTheyMustBeVisible()

        updateCallUI()
        scheduleControlTimeoutIfNecessary()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsAssert(self.groupCall === call)

        updateCallUI()
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssert(self.groupCall === call)

        let title: String

        switch reason {
        case .deviceExplicitlyDisconnected:
            dismissCall(shouldHangUp: false)
            return

        case .hasMaxDevices:
            if let maxDevices = ringRtcCall.maxDevices {
                let formatString = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_%d",
                    tableName: "PluralAware",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                title = String.localizedStringWithFormat(formatString, maxDevices)
            } else {
                title = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
            }

        case .removedFromCall:
            // [CallLink] TODO: .
            fallthrough

        case .deniedRequestToJoinCall:
            // [CallLink] TODO: .
            fallthrough

        case
                .serverExplicitlyDisconnected,
                .callManagerIsBusy,
                .sfuClientFailedToJoin,
                .failedToCreatePeerConnectionFactory,
                .failedToNegotiateSrtpKeys,
                .failedToCreatePeerConnection,
                .failedToStartPeerConnection,
                .failedToUpdatePeerConnection,
                .failedToSetMaxSendBitrate,
                .iceFailedWhileConnecting,
                .iceFailedAfterConnected,
                .serverChangedDemuxId:
            Logger.warn("Group call ended with reason \(reason)")
            title = OWSLocalizedString(
                "GROUP_CALL_UNEXPECTEDLY_ENDED",
                comment: "An error displayed to the user when the group call unexpectedly ends."
            )
        }

        let actionSheet = ActionSheetController(title: title)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okButton,
            style: .default,
            handler: { [weak self] _ in
                guard reason == .hasMaxDevices else { return }
                self?.dismissCall()
            }
        ))
        presentActionSheet(actionSheet)

        showCallControlsIfTheyMustBeVisible()
        updateCallUI()
    }

    func groupCallReceivedReactions(_ call: GroupCall, reactions: [SignalRingRTC.Reaction]) {
        owsAssert(self.groupCall === call)
        let localAci = databaseStorage.read { tx in
            return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
        }
        guard let localAci else {
            owsFailDebug("Local user is in call but doesn't have ACI!")
            return
        }
        let mappedReactions = databaseStorage.read { tx in
            return reactions.map { reaction in
                let name: String
                let aci: Aci
                if
                    let remoteDeviceState = ringRtcCall.remoteDeviceStates[reaction.demuxId],
                    remoteDeviceState.aci != localAci
                {
                    name = contactsManager.displayName(for: remoteDeviceState.address, tx: tx).resolvedValue()
                    aci = remoteDeviceState.aci
                } else {
                    name = CommonStrings.you
                    aci = localAci
                }
                return Reaction(
                    emoji: reaction.value,
                    name: name,
                    aci: aci,
                    timestamp: Date.timeIntervalSinceReferenceDate
                )
            }
        }
        self.reactionsSink.addReactions(reactions: mappedReactions)
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        self.raisedHandsToast.raisedHands = raisedHands
        self.updateCallUI(shouldAnimateViewFrames: true)
    }

    func handleUntrustedIdentityError(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsAssert(self.groupCall === call)

        if !hasUnresolvedSafetyNumberMismatch {
            hasUnresolvedSafetyNumberMismatch = true
            resolveSafetyNumberMismatch()
        }
    }
}

// MARK: CallHeaderDelegate

extension GroupCallViewController: CallHeaderDelegate {
    func didTapBackButton() {
        if groupCall.hasJoinedOrIsWaitingForAdminApproval {
            isCallMinimized = true
            WindowManager.shared.leaveCallView()
            // This ensures raised hands are removed
            updateCallUI()
        } else {
            dismissCall()
        }
    }

    func didTapMembersButton() {
        switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            let sheet = GroupCallMemberSheet(call: call, groupThreadCall: groupThreadCall)
            present(sheet, animated: true)
        case .callLink:
            owsFail("[CallLink] TODO: Add Info button for Call Link calls")
        }
    }
}

// MARK: RaisedHandsToastDelegate

extension GroupCallViewController: RaisedHandsToastDelegate {
    func didTapViewRaisedHands() {
        self.didTapMembersButton()
    }

    func raisedHandsToastDidChangeHeight(withAnimation: Bool) {
        self.updateCallUI(shouldAnimateViewFrames: withAnimation)
    }
}

// MARK: GroupCallVideoOverflowDelegate

extension GroupCallViewController: GroupCallVideoOverflowDelegate {
    var firstOverflowMemberIndex: Int {
        if scrollView.contentOffset.y >= view.height {
            return 1
        } else {
            return videoGrid.maxItems
        }
    }
}

// MARK: UIScrollViewDelegate

extension GroupCallViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // If we changed pages, update the overflow view.
        if scrollView.contentOffset.y == 0 || scrollView.contentOffset.y == view.height {
            videoOverflow.reloadData()
            updateCallUI(shouldAnimateViewFrames: true)
        }

        if isAutoScrollingToScreenShare {
            isAutoScrollingToScreenShare = scrollView.contentOffset.y != speakerView.frame.origin.y
        }

        updateSwipeToastView()
    }
}

// MARK: CallControlsDelegate

extension GroupCallViewController: CallControlsDelegate {
    func didPressRing() {
        switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            if groupThreadCall.ringRestrictions.isEmpty {
                // Refresh the call header.
                callHeader.groupCallLocalDeviceStateChanged(groupThreadCall)
            } else if groupThreadCall.ringRestrictions.contains(.groupTooLarge) {
                let toast = ToastController(text: OWSLocalizedString("GROUP_CALL_TOO_LARGE_TO_RING", comment: "Text displayed when trying to turn on ringing when calling a large group."))
                toast.presentToastView(from: .top, of: view, inset: view.safeAreaInsets.top + 8)
            }
        case .callLink:
            owsFail("Can't ring a call link")
        }
    }

    func didPressJoin() {
        if call.isFull {
            let text: String
            if let maxDevices = ringRtcCall.maxDevices {
                let formatString = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_%d",
                    tableName: "PluralAware",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                text = String.localizedStringWithFormat(formatString, maxDevices)
            } else {
                text = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
            }

            let toastController = ToastController(text: text)
            // Leave the toast up longer than usual because this message is pretty long.
            toastController.presentToastView(
                from: .top,
                of: view,
                inset: view.safeAreaInsets.top + 8,
                dismissAfter: .seconds(8)
            )
            return
        }

        presentSafetyNumberChangeSheetIfNecessary { [weak self] success in
            guard let self = self else { return }
            guard success else { return }
            self.callService.joinGroupCallIfNecessary(self.call, groupCall: self.groupCall)
        }
    }

    func didPressHangup() {
        didHangupCall()
    }

    func didPressMore() {
        if self.callControlsOverflowView.isHidden {
            self.callControlsDisplayState = .callControlsAndOverflow
        } else {
            self.callControlsDisplayState = .callControlsOnly
        }
    }
}

// MARK: CallMemberErrorPresenter

extension GroupCallViewController: CallMemberErrorPresenter {
    func presentErrorSheet(title: String, message: String) {
        let actionSheet = ActionSheetController(title: title, message: message, theme: .translucentDark)
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))
        presentActionSheet(actionSheet)
    }
}

// MARK: AnimatableLocalMemberViewDelegate

extension GroupCallViewController: AnimatableLocalMemberViewDelegate {
    var enclosingBounds: CGRect {
        return self.view.bounds
    }

    var remoteDeviceCount: Int {
        return ringRtcCall.remoteDeviceStates.count
    }

    func animatableLocalMemberViewDidCompleteExpandAnimation(_ localMemberView: CallMemberView) {
        self.expandedPipFrame = localMemberView.frame
        self.isPipAnimationInProgress = false
        performRetroactiveUiUpdateIfNecessary()
    }

    func animatableLocalMemberViewDidCompleteShrinkAnimation(_ localMemberView: CallMemberView) {
        self.expandedPipFrame = nil
        self.isPipAnimationInProgress = false
        performRetroactiveUiUpdateIfNecessary()
    }

    private func performRetroactiveUiUpdateIfNecessary() {
        if self.shouldRelayoutAfterPipAnimationCompletes {
            if
                let postAnimationUpdateMemberViewFramesSize,
                let postAnimationUpdateMemberViewFramesControlsAreHidden
            {
                updateMemberViewFrames(
                    size: postAnimationUpdateMemberViewFramesSize,
                    controlsAreHidden: postAnimationUpdateMemberViewFramesControlsAreHidden
                )
                self.postAnimationUpdateMemberViewFramesSize = nil
                self.postAnimationUpdateMemberViewFramesControlsAreHidden = nil
            }

            self.shouldRelayoutAfterPipAnimationCompletes = false
        }
    }

    func animatableLocalMemberViewWillBeginAnimation(_ localMemberView: CallMemberView) {
        self.isPipAnimationInProgress = true
        self.flipCameraTooltipManager.dismissTooltip()
    }
}

// MARK: - CallControlsOverflowPresenter

extension GroupCallViewController: CallControlsOverflowPresenter {
    func callControlsOverflowWillAppear() {
        self.controlTimeoutTimer?.invalidate()
        self.controlTimeoutTimer = nil
    }

    func callControlsOverflowDidDisappear() {
        self.scheduleControlTimeoutIfNecessary()
    }

    func willSendReaction() {
        self.callControlsDisplayState = .callControlsOnly
    }

    func didTapRaiseOrLowerHand() {
        self.callControlsDisplayState = .callControlsOnly
    }
}
