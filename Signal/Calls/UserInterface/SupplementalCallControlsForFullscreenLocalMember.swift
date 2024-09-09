//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import SignalUI
import UIKit

/// Once at least one remote member joins a call, the local member's video
/// reduces down to a pip, which includes certain call controls such as
/// the flip camera button (with more to come, per future designs). While
/// the local member is alone (either because they're in the lobby or
/// because they're the only one in the call), they're fullscreen, and
/// those call controls need to be somewhere! This view is the place!
class SupplementalCallControlsForFullscreenLocalMember: UIView {
    private lazy var flipCameraCircleView: CircleBlurView = {
        let circleView = CircleBlurView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        circleView.backgroundColor = CallButton.unselectedBackgroundColor
        circleView.isUserInteractionEnabled = false
        return circleView
    }()

    private lazy var flipCameraImageView = {
        let imageView = UIImageView(image: UIImage(named: "switch-camera-28"))
        imageView.tintColor = .ows_white
        imageView.autoSetDimension(
            .height,
            toSize: 24
        )
        imageView.autoMatch(.width, to: .height, of: imageView)
        return imageView
    }()

    private lazy var flipCameraButton: UIButton = {
        flipCameraCircleView.contentView.addSubview(flipCameraImageView)
        flipCameraImageView.autoCenterInSuperview()
        let button = UIButton()
        button.addSubview(flipCameraCircleView)
        flipCameraCircleView.autoPinEdgesToSuperviewEdges()

        button.autoSetDimension(
            .height,
            toSize: 48
        )
        button.autoMatch(.width, to: .height, of: button)
        button.accessibilityLabel = flipCameraButtonAccessibilityLabel
        button.addTarget(self, action: #selector(didPressFlipCamera), for: .touchUpInside)
        return button
    }()

    @objc
    private func didPressFlipCamera() {
        if let isUsingFrontCamera = call.videoCaptureController.isUsingFrontCamera {
            callService.updateCameraSource(call: call, isUsingFrontCamera: !isUsingFrontCamera)
        }
    }

    private var flipCameraButtonAccessibilityLabel: String {
        return OWSLocalizedString(
            "CALL_VIEW_SWITCH_CAMERA_DIRECTION",
            comment: "Accessibility label to toggle front- vs. rear-facing camera"
        )
    }

    private let call: SignalCall
    private let groupCall: GroupCall
    private let callService: CallService

    private enum Constants {
        static let trailingPadding: CGFloat = 16
    }

    init(
        call: SignalCall,
        groupCall: GroupCall,
        callService: CallService
    ) {
        self.call = call
        self.groupCall = groupCall
        self.callService = callService
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false

        addSubview(flipCameraButton)
        flipCameraButton.autoPinEdges(toSuperviewEdgesExcludingEdge: .leading)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self {
            return nil
        }
        return view
    }

    // MARK: - Required

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
