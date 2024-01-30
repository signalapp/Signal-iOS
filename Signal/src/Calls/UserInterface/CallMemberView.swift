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
        memberType: CallMemberView.ConfigurationType
    )
    func rotateForPhoneOrientation(_ rotationAngle: CGFloat)
    func updateDimensions()
    func clearConfiguration()
}

class CallMemberView: UIView {
    private let callMemberCameraOffView: CallMemberCameraOffView
    private let callMemberVideoView: CallMemberVideoView
    private let callMemberChromeOverlayView: CallMemberChromeOverlayView

    /// Must be specified with the lowest view first; views will be added
    /// as subviews in the order they are given.
    private var orderedComposableViews = [CallMemberComposableView]()

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDimensions()
    }

    private let type: CallMemberVideoView.MemberType

    init(type: CallMemberVideoView.MemberType) {
        self.type = type
        self.callMemberCameraOffView = CallMemberCameraOffView()
        self.callMemberVideoView = CallMemberVideoView(type: type)
        self.callMemberChromeOverlayView = CallMemberChromeOverlayView()
        super.init(frame: .zero)
        switch type {
        case .local:
            self.orderedComposableViews = [
                callMemberCameraOffView,
                callMemberVideoView,
                callMemberChromeOverlayView
            ]
        case .remote(_):
            self.orderedComposableViews = [
                callMemberCameraOffView,
                callMemberVideoView,
                // TODO: Add waiting and error views
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

    /// Not to be confused with ``CallMemberVideoView.MemberType``, which is used on
    /// init. This is an imperfect solution to the issue of (group,individual)x(local,remote)
    /// call member views having different needs for set up and configuration. The alternative
    /// is having optional params on `init` and `configure`.
    /// TODO: Eventually iterate to a point that the enum params can become non-optional
    /// `configure` params.
    enum ConfigurationType {
        case local
        case remote(RemoteDeviceState, CallMemberVisualContext)
    }

    private var hasBeenConfigured = false
    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: ConfigurationType
    ) {
        hasBeenConfigured = true
        switch memberType {
        case .local:
            guard case .local = self.type else {
                owsAssertBeta(false, "Member type on init must match member type on config!")
                return
            }
            layer.shadowOffset = .zero
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 4
            layer.cornerRadius = isFullScreen ? 0 : 10
        case .remote(_, _):
            guard case .remote = self.type else {
                owsAssertBeta(false, "Member type on init must match member type on config!")
                return
            }
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
        guard hasBeenConfigured else { return }
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
}
