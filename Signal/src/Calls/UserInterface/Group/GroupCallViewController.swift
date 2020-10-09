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
    private let localGroupMemberView = LocalGroupMemberView()

    // TODO:
    private var speakerView = UIView()

    init(call: SignalCall) {
        // TODO: Eventually unify UI for group and individual calls
        owsAssertDebug(call.isGroupCall)

        self.call = call
        self.thread = Self.databaseStorage.uiRead { transaction in
            let threadId = TSGroupThread.threadId(fromGroupId: call.groupCall.groupId)
            return TSGroupThread.anyFetchGroupThread(uniqueId: threadId, transaction: transaction)
        }

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
                    return owsFailDebug("Failed to build g roup call")
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

        // By default, start by showing the lobby.
        showLobby(isJoining: false)
    }

    func updateCallUI() {
        let localDevice = groupCall.localDevice

        localGroupMemberView.configure(device: localDevice, session: call.videoCaptureController.captureSession)

        switch localDevice.connectionState {
        case .connected:
            break
        case .connecting, .disconnected, .reconnecting:
            // todo: show spinner
            return
        }

        switch localDevice.joinState {
        case .joined:
            showVideoGrid()
        case .notJoined:
            showLobby(isJoining: false)
        case .joining:
            showLobby(isJoining: true)
        }
    }

    private var hasShownVideoGrid = false
    func showVideoGrid() {
        if !hasShownVideoGrid {
            view.insertSubview(videoGrid, belowSubview: localGroupMemberView)
            videoGrid.autoPinWidthToSuperview()
            videoGrid.autoPinEdge(toSuperviewMargin: .top)
            videoGrid.autoPinEdge(.bottom, to: .top, of: callControls, withOffset: 0)

            localGroupMemberView.removeFromSuperview()
            // TODO: make pip
        }
    }

    private var hasShownLobby = false
    func showLobby(isJoining: Bool) {
        // Once the user has joined, they should never be able
        // to returnt to the lobby.
        owsAssertDebug(!hasShownVideoGrid)

        if !hasShownLobby {
            hasShownLobby = true
            view.addSubview(localGroupMemberView)
            localGroupMemberView.autoPinEdgesToSuperviewEdges()

            view.addSubview(callHeader)
            callHeader.autoPinWidthToSuperview()
            callHeader.autoPinEdge(toSuperviewEdge: .top)

            view.addSubview(callControls)
            callControls.autoPinWidthToSuperview()
            callControls.autoPinEdge(toSuperviewEdge: .bottom)
        }
    }

    func leaveCall() {
        callService.terminate(call: call)

        OWSWindowManager.shared.endCall(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

extension GroupCallViewController: CallViewControllerWindowReference {
    var localVideoViewReference: UIView {
        // TODO:
        localGroupMemberView
    }

    var remoteVideoViewReference: UIView {
        // TODO:
        speakerView
    }

    var remoteVideoAddress: SignalServiceAddress {
        // TODO: get speaker
        guard let firstMember = groupCall.joinedGroupMembers.first else {
            return tsAccountManager.localAddress!
        }
        return SignalServiceAddress(uuid: firstMember)
    }

    func returnFromPip(pipWindow: UIWindow) {
        // TODO:
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

    }

    func groupCallJoinedGroupMembersChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)
    }

    func groupCallUpdateSfuInfo(_ call: SignalCall) {}
    func groupCallUpdateGroupMembershipProof(_ call: SignalCall) {}
    func groupCallUpdateGroupMembers(_ call: SignalCall) {}

    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}
}

extension GroupCallViewController: CallControlsDelegate {
    func didPressHangup(sender: UIButton) {
        leaveCall()
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
        leaveCall()
    }

    func didPressJoin(sender: UIButton) {
        groupCall.join()
    }
}

extension GroupCallViewController: CallHeaderDelegate {
    func didTapBackButton() {
        OWSWindowManager.shared.leaveCallView()
    }

    func didTapMembersButton() {

    }
}
