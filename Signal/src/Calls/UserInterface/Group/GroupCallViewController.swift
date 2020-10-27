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
    private var callService: CallService { AppEnvironment.shared.callService }

    private lazy var videoGrid = GroupCallVideoGrid(call: call)
    private lazy var videoOverflow = GroupCallVideoOverflow(call: call, delegate: self)

    private let localMemberView = GroupCallLocalMemberView()
    private let speakerView = GroupCallRemoteMemberView()

    private var speakerPage = UIView()

    private let scrollView = UIScrollView()

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
        scrollView.autoPinEdgesToSuperviewEdges()

        view.addSubview(callHeader)
        callHeader.autoPinWidthToSuperview()
        callHeader.autoPinEdge(toSuperviewEdge: .top)

        view.addSubview(callControls)
        callControls.autoPinWidthToSuperview()
        callControls.autoPinEdge(toSuperviewEdge: .bottom)

        view.addSubview(videoOverflow)
        videoOverflow.autoPinEdge(toSuperviewEdge: .leading)
        videoOverflow.autoPinEdge(
            toSuperviewEdge: .trailing,
            withInset: GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.pipSize.aspectRatio + 4
        )
        videoOverflow.autoPinEdge(.bottom, to: .top, of: callControls)

        scrollView.addSubview(videoGrid)
        scrollView.addSubview(speakerPage)

        updateCallUI()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.updateCallUI(size: size)
            self.videoGrid.reloadData()
            self.videoOverflow.reloadData()
        }, completion: nil)
    }

    private var hasOverflowMembers: Bool { videoGrid.maxItems < groupCall.remoteDeviceStates.count }

    private func updateScrollViewFrames(size: CGSize? = nil) {
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
                height: size.height - view.safeAreaInsets.top - callControls.height - (hasOverflowMembers ? videoOverflow.height + 16 : 0)
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

    private func updateMemberViewFrames(size: CGSize? = nil) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        speakerPage.subviews.forEach { $0.removeFromSuperview() }
        localMemberView.removeFromSuperview()

        switch groupCall.localDeviceState.joinState {
        case .joined:
            if let speakerState = groupCall.sortedRemoteDeviceStates.first {
                speakerPage.addSubview(speakerView)
                speakerView.frame = CGRect(origin: .zero, size: size)
                speakerView.configure(call: call, device: speakerState, isFullScreen: true)

                view.addSubview(localMemberView)

                if groupCall.remoteDeviceStates.count > 1 {
                    let pipWidth = GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.pipSize.aspectRatio
                    let pipHeight = GroupCallVideoOverflow.itemHeight
                    let shouldShiftUp = !hasOverflowMembers && scrollView.contentOffset.y < view.height
                    localMemberView.frame = CGRect(
                        x: size.width - pipWidth - 16,
                        y: videoOverflow.frame.origin.y + (shouldShiftUp ? -16 : 0),
                        width: pipWidth,
                        height: pipHeight
                    )
                } else {
                    let pipWidth = ReturnToCallViewController.pipSize.width
                    let pipHeight = ReturnToCallViewController.pipSize.height

                    localMemberView.frame = CGRect(
                        x: size.width - pipWidth - 16,
                        y: callControls.frame.minY - pipHeight,
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

        updateMemberViewFrames(size: size)
        updateScrollViewFrames(size: size)
    }

    func dismissCall() {
        callService.terminate(call: call)

        OWSWindowManager.shared.endCall(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
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

        updateCallUI()

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
        callUIAdapter.audioService.requestSpeakerphone(isEnabled: sender.isSelected)
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
        groupCall.join()
    }
}

extension GroupCallViewController: CallHeaderDelegate {
    func didTapBackButton() {
        if groupCall.localDeviceState.joinState == .joined {
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
    }
}
