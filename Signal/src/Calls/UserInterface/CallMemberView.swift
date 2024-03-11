//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalRingRTC
import SignalUI

enum CallMemberVisualContext: Equatable {
    case videoGrid, videoOverflow, speaker
}

protocol CallMemberComposableView: UIView {
    func configure(
        call: SignalCall,
        isFullScreen: Bool,
        memberType: CallMemberView.MemberType
    )
    func rotateForPhoneOrientation(_ rotationAngle: CGFloat)
    func updateDimensions()
    func clearConfiguration()
}

class CallMemberView: UIView, CallMemberView_GroupBridge, CallMemberView_IndividualRemoteBridge, CallMemberView_IndividualLocalBridge {
    private let callMemberCameraOffView: CallMemberCameraOffView
    private let callMemberVideoView: CallMemberVideoView
    private let callMemberWaitingAndErrorView: CallMemberWaitingAndErrorView
    private let callMemberChromeOverlayView: CallMemberChromeOverlayView

    /// Must be specified with the lowest view first; views will be added
    /// as subviews in the order they are given.
    private var orderedComposableViews = [CallMemberComposableView]()

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDimensions()
    }

    private let type: MemberType

    init(type: MemberType) {
        self.type = type
        self.callMemberCameraOffView = CallMemberCameraOffView(type: type)
        self.callMemberVideoView = CallMemberVideoView(type: type)
        self.callMemberWaitingAndErrorView = CallMemberWaitingAndErrorView()
        self.callMemberChromeOverlayView = CallMemberChromeOverlayView()

        super.init(frame: .zero)
        switch type {
        case .local, .remoteInIndividual:
            self.orderedComposableViews = [
                callMemberCameraOffView,
                callMemberVideoView,
                callMemberChromeOverlayView
            ]
        case .remoteInGroup:
            self.orderedComposableViews = [
                callMemberCameraOffView,
                callMemberVideoView,
                callMemberWaitingAndErrorView,
                callMemberChromeOverlayView
            ]
        }

        backgroundColor = .ows_gray90
        clipsToBounds = true

        self.orderedComposableViews.forEach { view in
            self.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateOrientationForPhone),
            name: CallService.phoneOrientationDidChange,
            object: nil
        )
    }

    @objc
    private func updateOrientationForPhone(_ notification: Notification) {
        let rotationAngle = notification.object as! CGFloat

        if window == nil {
            self.orderedComposableViews.forEach { view in
                view.rotateForPhoneOrientation(rotationAngle)
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.orderedComposableViews.forEach { view in
                    view.rotateForPhoneOrientation(rotationAngle)
                }
            }
        }
    }

    enum MemberType {
        case local
        case remoteInGroup(RemoteDeviceState?, CallMemberVisualContext)
        case remoteInIndividual
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: MemberType
    ) {
        switch memberType {
        case .local:
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 4
            layer.cornerRadius = isFullScreen ? 0 : 10
        case .remoteInGroup(_, _),
             .remoteInIndividual:
            break
        }

        self.orderedComposableViews.forEach { view in
            view.configure(
                call: call,
                isFullScreen: isFullScreen,
                memberType: memberType
            )
        }
    }

    private func updateDimensions() {
        self.orderedComposableViews.forEach { view in
            view.updateDimensions()
        }
    }

    func clearConfiguration() {
        self.orderedComposableViews.forEach { view in
            view.clearConfiguration()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: CallMemberView_GroupBridge

    func cleanupVideoViews() {
        self.callMemberVideoView.clearConfiguration()
    }

    func configureRemoteVideo(device: RemoteDeviceState, context: CallMemberVisualContext) {
        self.callMemberVideoView.configureRemoteVideo(
            device: device,
            context: context
        )
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

    // MARK: CallMemberView_IndividualRemoteBridge

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
        if let remoteVideoView = self.callMemberVideoView.remoteVideoViewIfApplicable() {
            return remoteVideoView
        }
        return nil
    }
}

/// For both local and remote call member views in group calls.
protocol CallMemberView_GroupBridge: UIView {
    var isCallMinimized: Bool { get set }
    var errorPresenter: CallMemberErrorPresenter? { get set }
    func cleanupVideoViews()
    func configureRemoteVideo(device: RemoteDeviceState, context: CallMemberVisualContext)
    func clearConfiguration()
}

protocol CallMemberView_IndividualRemoteBridge: UIView {
    var isGroupCall: Bool { get set }
    var isScreenShare: Bool { get set }
    var isFullScreen: Bool { get set }
    var remoteVideoView: RemoteVideoView? { get }
    func configure(
        call: SignalCall,
        isFullScreen: Bool,
        memberType: CallMemberView.MemberType
    )
}

protocol CallMemberView_IndividualLocalBridge: UIView {
    func configure(
        call: SignalCall,
        isFullScreen: Bool,
        memberType: CallMemberView.MemberType
    )
}
