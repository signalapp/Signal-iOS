//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalRingRTC
import SignalUI

// TODO: Eventually add 1:1 call support to this view
// and replace CallViewController
class GroupCallViewController: UIViewController {
    private let call: SignalCall
    private var groupCall: GroupCall { call.groupCall }
    private lazy var callControls = CallControls(call: call, delegate: self)
    private lazy var incomingCallControls = IncomingCallControls(video: true, delegate: self)
    private var incomingCallControlsConstraint: NSLayoutConstraint?
    private lazy var noVideoIndicatorView: UIStackView = createNoVideoIndicatorView()
    private lazy var callHeader = CallHeader(call: call, delegate: self)
    private lazy var notificationView = GroupCallNotificationView(call: call)

    private lazy var videoGrid = GroupCallVideoGrid(call: call)
    private lazy var videoOverflow = GroupCallVideoOverflow(call: call, delegate: self)

    private let localMemberView = GroupCallLocalMemberView()
    private let speakerView = GroupCallRemoteMemberView(mode: .speaker)

    private var didUserEverSwipeToSpeakerView = true
    private var didUserEverSwipeToScreenShare = true
    private let swipeToastView = GroupCallSwipeToastView()

    private var speakerPage = UIView()

    private let scrollView = UIScrollView()

    private var isCallMinimized = false {
        didSet { speakerView.isCallMinimized = isCallMinimized }
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

    lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTouchRootView))
    lazy var videoOverflowTopConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .top)
    lazy var videoOverflowTrailingConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .trailing)

    var shouldRemoteVideoControlsBeHidden = false {
        didSet { updateCallUI() }
    }
    var hasUnresolvedSafetyNumberMismatch = false
    var hasDismissed = false

    private var membersAtJoin: Set<SignalServiceAddress>?

    private static let keyValueStore = SDSKeyValueStore(collection: "GroupCallViewController")
    private static let didUserSwipeToSpeakerViewKey = "didUserSwipeToSpeakerView"
    private static let didUserSwipeToScreenShareKey = "didUserSwipeToScreenShare"

    init(call: SignalCall) {
        // TODO: Eventually unify UI for group and individual calls
        owsAssertDebug(call.isGroupCall)

        self.call = call

        super.init(nibName: nil, bundle: nil)

        call.addObserverAndSyncState(observer: self)

        videoGrid.memberViewDelegate = self
        videoOverflow.memberViewDelegate = self
        speakerView.delegate = self
        localMemberView.delegate = self

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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    @discardableResult
    class func presentLobby(thread: TSGroupThread, videoMuted: Bool = false) -> Bool {
        guard tsAccountManager.isOnboarded else {
            Logger.warn("aborting due to user not being onboarded.")
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "YOU_MUST_COMPLETE_ONBOARDING_BEFORE_PROCEEDING",
                comment: "alert body shown when trying to use features in the app before completing registration-related setup."
            ))
            return false
        }

        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("could not identify frontmostViewController")
            return false
        }

        frontmostViewController.ows_askForMicrophonePermissions { granted in
            guard granted == true else {
                Logger.warn("aborting due to missing microphone permissions.")
                frontmostViewController.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            guard let groupCall = Self.callService.buildAndConnectGroupCallIfPossible(
                thread: thread, videoMuted: videoMuted
            ) else {
                return owsFailDebug("Failed to build group call")
            }

            let completion = {
                // Dismiss the group call tooltip
                self.preferences.setWasGroupCallTooltipShown()

                let vc = GroupCallViewController(call: groupCall)
                vc.modalTransitionStyle = .crossDissolve

                OWSWindowManager.shared.startCall(vc)
            }

            if videoMuted {
                completion()
            } else {
                frontmostViewController.ows_askForCameraPermissions { granted in
                    guard granted else {
                        Logger.warn("aborting due to missing camera permissions.")
                        return
                    }
                    completion()
                }
            }
        }

        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

        view.addSubview(noVideoIndicatorView)
        noVideoIndicatorView.autoHCenterInSuperview()
        // Be flexible on the vertical centering on a cramped screen.
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            noVideoIndicatorView.autoVCenterInSuperview()
        }
        noVideoIndicatorView.autoPinEdge(.top, to: .bottom, of: callHeader, withOffset: 8, relation: .greaterThanOrEqual)

        view.addSubview(notificationView)
        notificationView.autoPinEdgesToSuperviewEdges()

        view.addSubview(callControls)
        callControls.autoPinWidthToSuperview()
        callControls.autoPinEdge(toSuperviewEdge: .bottom)
        callControls.autoPinEdge(.top, to: .bottom, of: noVideoIndicatorView, withOffset: 8, relation: .greaterThanOrEqual)

        view.addSubview(incomingCallControls)
        incomingCallControls.autoPinWidthToSuperview()
        incomingCallControls.autoPinEdge(toSuperviewEdge: .bottom)
        // Save this constraint for manual activation/deactivation,
        // so we don't push the noVideoIndicatorView out of center if we aren't showing the incoming controls.
        incomingCallControlsConstraint = incomingCallControls.autoPinEdge(
            .top, to: .bottom, of: noVideoIndicatorView, withOffset: 8, relation: .greaterThanOrEqual)

        view.addSubview(videoOverflow)
        videoOverflow.autoPinEdge(toSuperviewEdge: .leading)

        scrollView.addSubview(videoGrid)
        scrollView.addSubview(speakerPage)

        scrollView.addSubview(swipeToastView)
        swipeToastView.autoPinEdge(.bottom, to: .bottom, of: videoGrid, withOffset: -22)
        swipeToastView.autoHCenterInSuperview()
        swipeToastView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        swipeToastView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        view.addGestureRecognizer(tapGesture)

        updateCallUI()
    }

    private func createNoVideoIndicatorView() -> UIStackView {
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.setTemplateImage(#imageLiteral(resourceName: "video-off-solid-28"), tintColor: .ows_white)

        let label = UILabel()
        label.font = .dynamicTypeCaption1
        label.text = OWSLocalizedString("CALLING_MEMBER_VIEW_YOUR_CAMERA_IS_OFF",
                                       comment: "Indicates to the user that their camera is currently off.")
        label.textAlignment = .center
        label.textColor = Theme.darkThemePrimaryColor

        let container = UIStackView(arrangedSubviews: [icon, label])
        if UIDevice.current.isIPhone5OrShorter {
            // Use a horizontal layout to save on vertical space.
            // Allow the icon to shrink below its natural size of 28pt...
            icon.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            container.axis = .horizontal
            container.spacing = 4
            // ...by always matching the label's height.
            container.alignment = .fill
        } else {
            // Use a simple vertical layout.
            icon.autoSetDimensions(to: CGSize(square: 28))
            container.axis = .vertical
            container.spacing = 10
            container.alignment = .center
            label.autoPinWidthToSuperview()
        }

        return container
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

        if let splitViewSnapshot = SignalApp.shared().snapshotSplitViewController(afterScreenUpdates: false) {
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

    private var hasOverflowMembers: Bool { videoGrid.maxItems < groupCall.remoteDeviceStates.count }

    private func updateScrollViewFrames(size: CGSize? = nil, controlsAreHidden: Bool) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        if groupCall.remoteDeviceStates.count < 2 || groupCall.localDeviceState.joinState != .joined {
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

            scrollView.isScrollEnabled = true
            videoGrid.isHidden = false
            videoGrid.frame = CGRect(
                x: 0,
                y: view.safeAreaInsets.top,
                width: size.width,
                height: size.height - view.safeAreaInsets.top - (controlsAreHidden ? 16 : callControls.height) - (hasOverflowMembers ? videoOverflow.height + 32 : 0)
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
        var trailingConstraintConstant = -(GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.pipSize.aspectRatio + 4)
        if view.width + trailingConstraintConstant > videoOverflow.contentSize.width {
            trailingConstraintConstant += 16
        }
        videoOverflowTrailingConstraint.constant = trailingConstraintConstant
        view.layoutIfNeeded()
    }

    private func updateMemberViewFrames(size: CGSize? = nil, controlsAreHidden: Bool) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        let yMax = (controlsAreHidden ? size.height - 16 : callControls.frame.minY) - 16

        videoOverflowTopConstraint.constant = yMax - videoOverflow.height

        updateVideoOverflowTrailingConstraint()

        localMemberView.removeFromSuperview()
        speakerView.removeFromSuperview()

        switch groupCall.localDeviceState.joinState {
        case .joined:
            if groupCall.remoteDeviceStates.count > 0 {
                speakerPage.addSubview(speakerView)
                speakerView.autoPinEdgesToSuperviewEdges()

                view.addSubview(localMemberView)

                if groupCall.remoteDeviceStates.count > 1 {
                    let pipWidth = GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.pipSize.aspectRatio
                    let pipHeight = GroupCallVideoOverflow.itemHeight
                    localMemberView.frame = CGRect(
                        x: size.width - pipWidth - 16,
                        y: videoOverflow.frame.origin.y,
                        width: pipWidth,
                        height: pipHeight
                    )
                } else {
                    let pipWidth = ReturnToCallViewController.pipSize.width
                    let pipHeight = ReturnToCallViewController.pipSize.height

                    localMemberView.frame = CGRect(
                        x: size.width - pipWidth - 16,
                        y: yMax - pipHeight,
                        width: pipWidth,
                        height: pipHeight
                    )
                }
            } else {
                speakerPage.addSubview(localMemberView)
                localMemberView.frame = CGRect(origin: .zero, size: size)
            }
        case .notJoined, .joining:
            speakerPage.addSubview(localMemberView)
            localMemberView.frame = CGRect(origin: .zero, size: size)
        }
    }

    func updateSwipeToastView() {
        let isSpeakerViewAvailable = groupCall.remoteDeviceStates.count >= 2 && groupCall.localDeviceState.joinState == .joined
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

    func updateCallUI(size: CGSize? = nil) {
        // Force load the view if it hasn't been yet.
        _ = self.view

        let localDevice = groupCall.localDeviceState

        localMemberView.configure(
            call: call,
            isFullScreen: localDevice.joinState != .joined || groupCall.remoteDeviceStates.isEmpty
        )

        if let speakerState = groupCall.remoteDeviceStates.sortedBySpeakerTime.first {
            speakerView.configure(
                call: call,
                device: speakerState
            )
        } else {
            speakerView.clearConfiguration()
        }

        guard !isCallMinimized else { return }

        let showNoVideoIndicator = groupCall.remoteDeviceStates.isEmpty && groupCall.isOutgoingVideoMuted
        // Hide the subviews of this view to collapse the stack.
        noVideoIndicatorView.subviews.forEach { $0.isHidden = !showNoVideoIndicator }

        if call.groupCallRingState.isIncomingRing {
            callControls.isHidden = true
            incomingCallControls.isHidden = false
            incomingCallControlsConstraint?.isActive = true
            // These views aren't visible at this point, but we need them to be configured anyway.
            updateMemberViewFrames(size: size, controlsAreHidden: true)
            updateScrollViewFrames(size: size, controlsAreHidden: true)
            return
        }

        if !incomingCallControls.isHidden {
            // We were showing the incoming call controls, but now we don't want to.
            // To make sure all views transition properly, pretend we were showing the regular controls all along.
            callControls.isHidden = false
            incomingCallControls.isHidden = true
            incomingCallControlsConstraint?.isActive = false
        }

        let hideRemoteControls = shouldRemoteVideoControlsBeHidden && !groupCall.remoteDeviceStates.isEmpty
        let remoteControlsAreHidden = callControls.isHidden && callHeader.isHidden
        if hideRemoteControls != remoteControlsAreHidden {
            callControls.isHidden = false
            callHeader.isHidden = false

            UIView.animate(withDuration: 0.15, animations: {
                self.callControls.alpha = hideRemoteControls ? 0 : 1
                self.callHeader.alpha = hideRemoteControls ? 0 : 1

                self.updateMemberViewFrames(size: size, controlsAreHidden: hideRemoteControls)
                self.updateScrollViewFrames(size: size, controlsAreHidden: hideRemoteControls)
                self.view.layoutIfNeeded()
            }) { _ in
                self.callControls.isHidden = hideRemoteControls
                self.callHeader.isHidden = hideRemoteControls
            }
        } else {
            updateMemberViewFrames(size: size, controlsAreHidden: hideRemoteControls)
            updateScrollViewFrames(size: size, controlsAreHidden: hideRemoteControls)
        }

        scheduleControlTimeoutIfNecessary()
        updateSwipeToastView()
    }

    func dismissCall(shouldHangUp: Bool = true) {
        if shouldHangUp {
            callService.callUIAdapter.localHangupCall(call)
        }

        guard !hasDismissed else {
            return
        }
        hasDismissed = true

        guard
            let splitViewSnapshot = SignalApp.shared().snapshotSplitViewController(afterScreenUpdates: false),
            view.superview?.insertSubview(splitViewSnapshot, belowSubview: view) != nil
        else {
            // This can happen if we're in the background when the call is dismissed (say, from CallKit).
            OWSWindowManager.shared.endCall(self)
            return
        }

        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        UIView.animate(withDuration: 0.2, animations: {
            self.view.alpha = 0
        }) { _ in
            splitViewSnapshot.removeFromSuperview()
            OWSWindowManager.shared.endCall(self)
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    // MARK: - Video control timeout

    @objc
    private func didTouchRootView(sender: UIGestureRecognizer) {
        shouldRemoteVideoControlsBeHidden = !shouldRemoteVideoControlsBeHidden
    }

    private var controlTimeoutTimer: Timer?
    private func scheduleControlTimeoutIfNecessary() {
        if  groupCall.remoteDeviceStates.isEmpty || shouldRemoteVideoControlsBeHidden {
            controlTimeoutTimer?.invalidate()
            controlTimeoutTimer = nil
        }

        guard controlTimeoutTimer == nil else { return }
        controlTimeoutTimer = .weakScheduledTimer(
            withTimeInterval: 5,
            target: self,
            selector: #selector(timeoutControls),
            userInfo: nil,
            repeats: false
        )
    }

    @objc
    private func timeoutControls() {
        controlTimeoutTimer?.invalidate()
        controlTimeoutTimer = nil

        guard !isCallMinimized && !groupCall.remoteDeviceStates.isEmpty && !shouldRemoteVideoControlsBeHidden else { return }
        shouldRemoteVideoControlsBeHidden = true
    }
}

extension GroupCallViewController: CallViewControllerWindowReference {
    var localVideoViewReference: UIView { localMemberView }
    var remoteVideoViewReference: UIView { speakerView }

    var remoteVideoAddress: SignalServiceAddress {
        guard let firstMember = groupCall.remoteDeviceStates.sortedByAddedTime.first else {
            return tsAccountManager.localAddress!
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

        guard let splitViewSnapshot = SignalApp.shared().snapshotSplitViewController(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot rootViewController")
        }

        guard let pipSnapshot = pipWindow.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot pip")
        }

        isCallMinimized = false
        shouldRemoteVideoControlsBeHidden = false

        animateReturnFromPip(pipSnapshot: pipSnapshot, pipFrame: pipWindow.frame, splitViewSnapshot: splitViewSnapshot)
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

    private func safetyNumberMismatchAddresses() -> [SignalServiceAddress] {
        databaseStorage.read { transaction in
            let addressesToCheck: [SignalServiceAddress]
            if groupCall.localDeviceState.joinState == .notJoined {
                // If we haven't joined the call yet, we want to alert for all members of the group
                addressesToCheck = call.thread.recipientAddresses(with: transaction)
            } else {
                // If we are in the call, we only care about safety numbers for the active call participants
                addressesToCheck = groupCall.remoteDeviceStates.map { $0.value.address }
            }

            return addressesToCheck.filter { memberAddress in
                identityManager.untrustedIdentityForSending(to: memberAddress, transaction: transaction) != nil
            }
        }
    }

    func resolveSafetyNumberMismatch() {
        let resendMediaKeysAndResetMismatch = { [unowned self] in
            self.groupCall.resendMediaKeys()
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
            let unresolvedAddresses = safetyNumberMismatchAddresses()
            guard !unresolvedAddresses.isEmpty else {
                // Spurious warning, maybe from delayed callbacks.
                resendMediaKeysAndResetMismatch()
                return
            }

            // If a problematic member was present at join, leaves, and then joins again,
            // we'll still treat them as having been there "since join", but that's okay.
            // It's not worth trying to track this more precisely.
            let atLeastOneUnresolvedPresentAtJoin = unresolvedAddresses.contains { membersAtJoin?.contains($0) ?? false }
            Self.notificationPresenter.notifyForGroupCallSafetyNumberChange(inThread: call.thread,
                                                                            presentAtJoin: atLeastOneUnresolvedPresentAtJoin)
        }
    }

    func presentSafetyNumberChangeSheetIfNecessary(completion: @escaping (Bool) -> Void) {
        let localDeviceHasNotJoined = groupCall.localDeviceState.joinState == .notJoined
        let addressesToAlert = safetyNumberMismatchAddresses()

        // There are no unverified addresses that we're currently concerned about. No need to show a sheet
        guard !addressesToAlert.isEmpty else { return completion(true) }

        if let existingSheet = presentedViewController as? SafetyNumberConfirmationSheet {
            // The set of untrusted addresses may have changed.
            // It's a bit clunky, but we'll just dismiss the existing sheet before putting up a new one.
            existingSheet.dismiss(animated: false)
        }

        let startCallString = OWSLocalizedString("GROUP_CALL_START_BUTTON", comment: "Button to start a group call")
        let joinCallString = OWSLocalizedString("GROUP_CALL_JOIN_BUTTON", comment: "Button to join an ongoing group call")
        let continueCallString = OWSLocalizedString("GROUP_CALL_CONTINUE_BUTTON", comment: "Button to continue an ongoing group call")
        let leaveCallString = OWSLocalizedString("GROUP_CALL_LEAVE_BUTTON", comment: "Button to leave a group call")
        let cancelString = CommonStrings.cancelButton

        let approveText: String
        let denyText: String
        if localDeviceHasNotJoined {
            approveText = call.ringRestrictions.contains(.callInProgress) ? joinCallString : startCallString
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
        ) { didApprove in
            completion(didApprove)
        }
        sheet.allowsDismissal = localDeviceHasNotJoined
        present(sheet, animated: true, completion: nil)
    }
}

extension GroupCallViewController: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateCallUI()

        switch call.groupCall.localDeviceState.joinState {
        case .joined:
            if membersAtJoin == nil {
                membersAtJoin = Set(call.groupCall.remoteDeviceStates.lazy.map { $0.value.address })
            }
        case .joining, .notJoined:
            membersAtJoin = nil
        }
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        isAnyRemoteDeviceScreenSharing = call.groupCall.remoteDeviceStates.values.first { $0.sharingScreen == true } != nil

        updateCallUI()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateCallUI()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        guard reason != .deviceExplicitlyDisconnected else {
            dismissCall(shouldHangUp: false)
            return
        }

        defer { updateCallUI() }

        let title: String

        if reason == .hasMaxDevices {
            if let maxDevices = groupCall.maxDevices {
                let formatString = OWSLocalizedString("GROUP_CALL_HAS_MAX_DEVICES_%d", tableName: "PluralAware",
                                                     comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                title = String.localizedStringWithFormat(formatString, maxDevices)
            } else {
                title = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
            }
        } else {
            owsFailDebug("Group call ended with reason \(reason)")
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
    }

    func callMessageSendFailedUntrustedIdentity(_ call: SignalCall) {
        AssertIsOnMainThread()
        guard call == self.call else { return owsFailDebug("Unexpected call \(call)") }

        if !hasUnresolvedSafetyNumberMismatch {
            hasUnresolvedSafetyNumberMismatch = true
            resolveSafetyNumberMismatch()
        }
    }
}

extension GroupCallViewController: CallControlsDelegate {
    func didPressHangup(sender: UIButton) {
        dismissCall()
    }

    func didPressAudioSource(sender: UIButton) {
        if callService.audioService.hasExternalInputs {
            callService.audioService.presentRoutePicker()
        } else {
            sender.isSelected = !sender.isSelected
            callService.audioService.requestSpeakerphone(call: self.call.groupCall, isEnabled: sender.isSelected)
        }
    }

    func didPressMute(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        callService.updateIsLocalAudioMuted(isLocalAudioMuted: sender.isSelected)
    }

    func didPressVideo(sender: UIButton) {
        sender.isSelected = !sender.isSelected

        callService.updateIsLocalVideoMuted(isLocalVideoMuted: !sender.isSelected)

        // When turning off video, default speakerphone to on.
        if !sender.isSelected && !callService.audioService.hasExternalInputs {
            callControls.audioSourceButton.isSelected = true
            callService.audioService.requestSpeakerphone(call: self.call.groupCall, isEnabled: true)
        }
    }

    func didPressRing(sender: UIButton) {
        if call.ringRestrictions.isEmpty {
            let oldShouldRing = sender.isSelected
            let newShouldRing = !oldShouldRing
            sender.isSelected = newShouldRing
            call.groupCallRingState = newShouldRing ? .shouldRing : .doNotRing

            // Refresh the call header.
            callHeader.groupCallLocalDeviceStateChanged(call)
        } else {
            if call.ringRestrictions.intersects([.notApplicable, .callInProgress]) {
                owsFailDebug("should not show the ring button at all")
            } else if call.ringRestrictions.contains(.groupTooLarge) {
                let toast = ToastController(text: OWSLocalizedString("GROUP_CALL_TOO_LARGE_TO_RING", comment: "Text displayed when trying to turn on ringing when calling a large group."))
                toast.presentToastView(from: .top, of: view, inset: view.safeAreaInsets.top + 8)
            } else {
                owsAssertDebug(call.ringRestrictions.isEmpty, "unknown ring restriction")
            }
        }
    }

    func didPressFlipCamera(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        callService.updateCameraSource(call: call, isUsingFrontCamera: !sender.isSelected)
    }

    func didPressJoin(sender: UIButton) {
        guard !call.groupCall.isFull else {
            let text: String
            if let maxDevices = call.groupCall.maxDevices {
                let formatString = OWSLocalizedString("GROUP_CALL_HAS_MAX_DEVICES_%d", tableName: "PluralAware",
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
            toastController.presentToastView(from: .top,
                                             of: view,
                                             inset: view.safeAreaInsets.top + 8,
                                             dismissAfter: .seconds(8))
            return
        }

        presentSafetyNumberChangeSheetIfNecessary { [weak self] success in
            guard let self = self else { return }
            if success {
                self.callService.joinGroupCallIfNecessary(self.call)
            }
        }
    }
}

extension GroupCallViewController: IncomingCallControlsDelegate {
    func didDeclineIncomingCall() {
        dismissCall()
    }

    func didAcceptIncomingCall(sender: UIButton) {
        // Explicitly unmute video in order to request permissions as needed.
        // (Audio is unmuted as part of the call UI adapter.)

        let videoMute = IncomingCallControls.VideoEnabledTag(rawValue: sender.tag) == .disabled
        callService.updateIsLocalVideoMuted(isLocalVideoMuted: videoMute)
        // When turning off video, default speakerphone to on.
        if videoMute && !callService.audioService.hasExternalInputs {
            callService.audioService.requestSpeakerphone(call: call.groupCall, isEnabled: true)
        }

        callService.callUIAdapter.answerCall(call)
    }
}

extension GroupCallViewController: CallHeaderDelegate {
    func didTapBackButton() {
        if groupCall.localDeviceState.joinState == .joined {
            isCallMinimized = true
            OWSWindowManager.shared.leaveCallView()
        } else {
            dismissCall()
        }
    }

    func didTapMembersButton() {
        let sheet = GroupCallMemberSheet(call: call)
        present(sheet, animated: true)
    }
}

extension GroupCallViewController: GroupCallVideoOverflowDelegate {
    var firstOverflowMemberIndex: Int {
        if scrollView.contentOffset.y >= view.height {
            return 1
        } else {
            return videoGrid.maxItems
        }
    }
}

extension GroupCallViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // If we changed pages, update the overflow view.
        if scrollView.contentOffset.y == 0 || scrollView.contentOffset.y == view.height {
            videoOverflow.reloadData()
            updateCallUI()
        }

        if isAutoScrollingToScreenShare {
            isAutoScrollingToScreenShare = scrollView.contentOffset.y != speakerView.frame.origin.y
        }

        updateSwipeToastView()
    }
}

extension GroupCallViewController: GroupCallMemberViewDelegate {
    func memberView(_ view: GroupCallMemberView, userRequestedInfoAboutError error: GroupCallMemberView.ErrorState) {
        let title: String
        let message: String

        switch error {
        case let .blocked(address):
            message = OWSLocalizedString(
                "GROUP_CALL_BLOCKED_ALERT_MESSAGE",
                comment: "Message body for alert explaining that a group call participant is blocked")

            let titleFormat = OWSLocalizedString(
                "GROUP_CALL_BLOCKED_ALERT_TITLE_FORMAT",
                comment: "Title for alert explaining that a group call participant is blocked. Embeds {{ user's name }}")
            let displayName = contactsManager.displayName(for: address)
            title = String(format: titleFormat, displayName)

        case let .noMediaKeys(address):
            message = OWSLocalizedString(
                "GROUP_CALL_NO_KEYS_ALERT_MESSAGE",
                comment: "Message body for alert explaining that a group call participant cannot be displayed because of missing keys")

            let titleFormat = OWSLocalizedString(
                "GROUP_CALL_NO_KEYS_ALERT_TITLE_FORMAT",
                comment: "Title for alert explaining that a group call participant cannot be displayed because of missing keys. Embeds {{ user's name }}")
            let displayName = contactsManager.displayName(for: address)
            title = String(format: titleFormat, displayName)
        }

        let actionSheet = ActionSheetController(title: title, message: message, theme: .translucentDark)
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))
        presentActionSheet(actionSheet)
    }
}
