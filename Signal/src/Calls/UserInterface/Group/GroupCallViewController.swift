//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

// TODO: Eventually add 1:1 call support to this view
// and replace CallViewController
class GroupCallViewController: UIViewController {
    private let thread: TSGroupThread?
    private let call: SignalCall
    private var groupCall: GroupCall { call.groupCall }
    private lazy var callControls = CallControls(call: call, delegate: self)
    private lazy var callHeader = CallHeader(call: call, delegate: self)

    private lazy var videoGrid = GroupCallVideoGrid(call: call)
    private lazy var videoOverflow = GroupCallVideoOverflow(call: call, delegate: self)

    private let localMemberView = GroupCallLocalMemberView()
    private let speakerView = GroupCallRemoteMemberView()

    private var speakerPage = UIView()

    private let scrollView = UIScrollView()

    private var isCallMinimized = false

    lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTouchRootView))
    lazy var videoOverflowTopConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .top)
    lazy var videoOverflowTrailingConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .trailing)

    var shouldRemoteVideoControlsBeHidden = false {
        didSet { updateCallUI() }
    }

    init(call: SignalCall) {
        // TODO: Eventually unify UI for group and individual calls
        owsAssertDebug(call.isGroupCall)

        self.call = call
        self.thread = call.thread as? TSGroupThread

        super.init(nibName: nil, bundle: nil)

        call.addObserverAndSyncState(observer: self)
    }

    @discardableResult
    @objc(presentLobbyForThread:)
    class func presentLobby(thread: TSGroupThread) -> Bool {
        guard tsAccountManager.isOnboarded() else {
            Logger.warn("aborting due to user not being onboarded.")
            OWSActionSheets.showActionSheet(title: NSLocalizedString(
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

            frontmostViewController.ows_askForCameraPermissions { granted in
                guard granted else {
                    Logger.warn("aborting due to missing camera permissions.")
                    return
                }

                guard let groupCall = AppEnvironment.shared.callService.buildAndConnectGroupCallIfPossible(
                        thread: thread
                ) else {
                    return owsFailDebug("Failed to build group call")
                }

                let vc = GroupCallViewController(call: groupCall)
                vc.modalTransitionStyle = .crossDissolve

                OWSWindowManager.shared.startCall(vc)
            }
        }

        return true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()

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

        view.addSubview(callControls)
        callControls.autoPinWidthToSuperview()
        callControls.autoPinEdge(toSuperviewEdge: .bottom)

        view.addSubview(videoOverflow)
        videoOverflow.autoPinEdge(toSuperviewEdge: .leading)

        scrollView.addSubview(videoGrid)
        scrollView.addSubview(speakerPage)

        view.addGestureRecognizer(tapGesture)

        updateCallUI()
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

    private func updateMemberViewFrames(size: CGSize? = nil, controlsAreHidden: Bool) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        let yMax = (controlsAreHidden ? size.height - 16 : callControls.frame.minY) - 16

        videoOverflowTopConstraint.constant = yMax - videoOverflow.height
        videoOverflowTrailingConstraint.constant = GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.pipSize.aspectRatio + 4
        view.layoutIfNeeded()

        localMemberView.removeFromSuperview()
        speakerView.removeFromSuperview()

        switch groupCall.localDeviceState.joinState {
        case .joined:
            if groupCall.sortedRemoteDeviceStates.count > 0 {
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

    func updateCallUI(size: CGSize? = nil) {
        let localDevice = groupCall.localDeviceState

        localMemberView.configure(
            device: localDevice,
            session: call.videoCaptureController.captureSession,
            isFullScreen: localDevice.joinState != .joined || groupCall.remoteDeviceStates.isEmpty
        )

        if let speakerState = groupCall.sortedRemoteDeviceStates.first {
            speakerView.configure(call: call, device: speakerState, isFullScreen: true)
        }

        guard !isCallMinimized else { return }

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
            }) { _ in
                self.callControls.isHidden = hideRemoteControls
                self.callHeader.isHidden = hideRemoteControls
            }
        } else {
            updateMemberViewFrames(size: size, controlsAreHidden: hideRemoteControls)
            updateScrollViewFrames(size: size, controlsAreHidden: hideRemoteControls)
        }

        scheduleControlTimeoutIfNecessary()
    }

    func dismissCall() {
        callService.terminate(call: call)

        OWSWindowManager.shared.endCall(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    // MARK: - Video control timeout

    @objc func didTouchRootView(sender: UIGestureRecognizer) {
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
        guard let firstMember = groupCall.sortedRemoteDeviceStates.first else {
            return tsAccountManager.localAddress!
        }
        return firstMember.address
    }

    @objc
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

        view.frame = pipFrame
        view.addSubview(pipSnapshot)
        pipSnapshot.autoPinEdgesToSuperviewEdges()

        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            pipSnapshot.alpha = 0
            self.view.frame = window.frame
            self.view.layoutIfNeeded()
        }) { _ in
            self.updateCallUI()
            splitViewSnapshot.removeFromSuperview()
            pipSnapshot.removeFromSuperview()
        }
    }
}

extension GroupCallViewController: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateCallUI()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateCallUI()
    }

    func groupCallJoinedMembersChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateCallUI()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        guard reason != .deviceExplicitlyDisconnected else { return }

        owsFailDebug("Group call ended with reason \(reason)")

        // TODO: Show better error to user?
        let actionSheet = ActionSheetController(
            title: NSLocalizedString(
                "GROUP_CALL_UNEXPECTEDLY_ENDED",
                comment: "An error displayed to the user when the group call unexpectedly ends."
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("OK", comment: ""),
            style: .default,
            handler: nil
        ))
        presentActionSheet(actionSheet)
    }

    func groupCallRequestMembershipProof(_ call: SignalCall) {}
    func groupCallRequestGroupMembers(_ call: SignalCall) {}

    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}
}

extension GroupCallViewController: CallControlsDelegate {
    func didPressHangup(sender: UIButton) {
        dismissCall()
    }

    func didPressAudioSource(sender: UIButton) {
        // TODO: Multiple Audio Sources
        sender.isSelected = !sender.isSelected
        callService.audioService.requestSpeakerphone(isEnabled: sender.isSelected)
    }

    func didPressMute(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        groupCall.isOutgoingAudioMuted = sender.isSelected
    }

    func didPressVideo(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        callService.updateIsLocalVideoMuted(isLocalVideoMuted: !sender.isSelected)
    }

    func didPressFlipCamera(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        callService.updateCameraSource(call: call, isUsingFrontCamera: !sender.isSelected)
    }

    func didPressCancel(sender: UIButton) {
        dismissCall()
    }

    func didPressJoin(sender: UIButton) {
        callService.joinGroupCallIfNecessary(call)
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
            ImpactHapticFeedback.impactOccured(style: .light)
        }
    }
}
