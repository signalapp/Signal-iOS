//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Foundation
import SignalRingRTC
import SignalServiceKit

class CallMemberVideoView: UIView, CallMemberComposableView {
    private let type: CallMemberView.MemberType

    private lazy var blurredAvatarBackgroundView = BlurredAvatarBackgroundView()

    init(type: CallMemberView.MemberType) {
        self.type = type
        super.init(frame: .zero)
        backgroundColor = .ows_black
        isUserInteractionEnabled = false
        switch type {
        case .local:
            let localVideoView = LocalVideoView()
            self.addSubview(localVideoView)
            localVideoView.contentMode = .scaleAspectFill
            self.callViewWrapper = .local(localVideoView)
        case .remoteInIndividual:
            let remoteVideoView = RemoteVideoView()
            remoteVideoView.isGroupCall = false
            self.addSubview(remoteVideoView)
            remoteVideoView.autoPinEdgesToSuperviewEdges()
            self.callViewWrapper = .remoteInIndividual(remoteVideoView)
        case .remoteInGroup:
            self.addSubview(blurredAvatarBackgroundView)
            self.blurredAvatarBackgroundView.autoPinEdgesToSuperviewEdges()
        }
    }

    private enum CallViewWrapper {
        case local(LocalVideoView)
        case remoteInIndividual(RemoteVideoView)
        case remoteInGroup(GroupCallRemoteVideoView)
    }
    private var callViewWrapper: CallViewWrapper?

    func remoteVideoViewIfApplicable() -> RemoteVideoView? {
        switch callViewWrapper {
        case .remoteInIndividual(let remoteVideoView):
            return remoteVideoView
        default:
            return nil
        }
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    ) {
        layer.cornerRadius = isFullScreen ? 0 : CallMemberView.Constants.defaultPipCornerRadius
        clipsToBounds = true
        switch type {
        case .local:
            self.isHidden = call.isOutgoingVideoMuted || AppEnvironment.shared.windowManagerRef.isCallInPip
            if case let .local(videoView) = callViewWrapper {
                videoView.captureSession = call.videoCaptureController.captureSession
            } else {
                owsFailDebug("This should not be called when we're dealing with a remote video!")
            }
        case .remoteInGroup(let context):
            guard let remoteGroupMemberDeviceState else { return }
            self.blurredAvatarBackgroundView.update(
                type: self.type,
                remoteGroupMemberDeviceState: remoteGroupMemberDeviceState
            )
            if remoteGroupMemberDeviceState.mediaKeysReceived, remoteGroupMemberDeviceState.videoTrack != nil {
                self.isHidden = (remoteGroupMemberDeviceState.videoMuted == true)
            }
            if !self.isHidden {
                configureRemoteVideo(device: remoteGroupMemberDeviceState, context: context)
            }
        case .remoteInIndividual(let individualCall):
            self.isHidden = !individualCall.isRemoteVideoEnabled
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
        } else if nil != callViewWrapper {
            owsFailDebug("Can only call configureRemoteVideo for groups!")
        }
        let callService = AppEnvironment.shared.callService!
        let remoteVideoView = callService.groupCallRemoteVideoManager.remoteVideoView(for: device, context: context)
        self.addSubview(remoteVideoView)
        self.callViewWrapper = .remoteInGroup(remoteVideoView)
        remoteVideoView.autoPinEdgesToSuperviewEdges()
        remoteVideoView.isScreenShare = device.sharingScreen == true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch callViewWrapper {
        case .local(let localVideoView):
            // Video rotations get funky when we use autolayout
            // for `localVideoView`.
            localVideoView.frame = bounds
        default:
            // There do not seem to be issues with remote member
            // views getting updated.
            break
        }
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {}

    func updateDimensions() {}

    func clearConfiguration() {
        self.blurredAvatarBackgroundView.clear()
        if unwrapVideoView()?.superview === self { unwrapVideoView()?.removeFromSuperview() }
        callViewWrapper = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
