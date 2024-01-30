//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import SignalMessaging
import SignalRingRTC

class CallMemberVideoView: UIView, CallMemberComposableView {
    /// See note on ```CallMemberView.Configurationtype```.
    enum MemberType {
        case local(SignalCall)
        case remote(isGroupCall: Bool)
    }

    init(type: MemberType) {
        super.init(frame: .zero)
        switch type {
        case .local(let call):
            let localVideoView = LocalVideoView(shouldUseAutolayout: true)
            localVideoView.captureSession = call.videoCaptureController.captureSession
            self.addSubview(localVideoView)
            localVideoView.contentMode = .scaleAspectFill
            localVideoView.autoPinEdgesToSuperviewEdges()
            self.callViewWrapper = .local(localVideoView)
        case .remote(let isGroupCall):
            if !isGroupCall {
                let remoteVideoView = RemoteVideoView()
                remoteVideoView.isGroupCall = false
                remoteVideoView.isUserInteractionEnabled = false
                self.addSubview(remoteVideoView)
                remoteVideoView.autoPinEdgesToSuperviewEdges()
                self.callViewWrapper = .remoteInIndividual(remoteVideoView)
            }
            // The view for group calls is set upon `configure`.
        }
    }

    private enum CallViewWrapper {
        case local(LocalVideoView)
        case remoteInIndividual(RemoteVideoView)
        case remoteInGroup(GroupCallRemoteVideoView)
    }
    private var callViewWrapper: CallViewWrapper?

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: CallMemberView.ConfigurationType
    ) {
        self.isHidden = call.isOutgoingVideoMuted
        switch memberType {
        case .local:
            if case let .local(videoView) = callViewWrapper {
                videoView.captureSession = call.videoCaptureController.captureSession
            } else {
                owsFailDebug("This should not be called when we're dealing with a remote video!")
            }
        case .remote(let remoteDeviceState, let context):
            if remoteDeviceState.mediaKeysReceived, remoteDeviceState.videoTrack != nil {
                self.isHidden = (remoteDeviceState.videoMuted == true)
            }
            if !self.isHidden {
                configureRemoteVideo(device: remoteDeviceState, context: context)
            }
        }
    }

    private func unwrapVideoView() -> UIView? {
        switch self.callViewWrapper {
        case .local(let localVideoView):
            return localVideoView
        case .remoteInIndividual(let remoteVideoView):
            return remoteVideoView
        case .remoteInGroup(let groupCallRemoteVideoView):
            return groupCallRemoteVideoView
        case .none:
            return nil
        }
    }

    func configureRemoteVideo(
        device: RemoteDeviceState,
        context: CallMemberVisualContext
    ) {
        if case let .remoteInGroup(videoView) = callViewWrapper {
            if videoView.superview == self { videoView.removeFromSuperview() }
        } else {
            owsFailDebug("Can only call configureRemoteVideo for groups!")
        }
        let remoteVideoView = callService.groupCallRemoteVideoManager.remoteVideoView(for: device, context: context)
        self.addSubview(remoteVideoView)
        self.callViewWrapper = .remoteInGroup(remoteVideoView)
        remoteVideoView.autoPinEdgesToSuperviewEdges()
        remoteVideoView.isScreenShare = device.sharingScreen == true
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating.
    }

    func updateDimensions() {}

    func clearConfiguration() {
        if unwrapVideoView()?.superview === self { unwrapVideoView()?.removeFromSuperview() }
        callViewWrapper = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
