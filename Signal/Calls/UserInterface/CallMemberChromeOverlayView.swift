//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

class CallMemberChromeOverlayView: UIView, CallMemberComposableView {
    private var call: SignalCall?
    private var type: CallMemberView.MemberType
    private var callService: CallService { AppEnvironment.shared.callService }

    init(type: CallMemberView.MemberType) {
        self.type = type
        switch type {
        case .local, .remoteInIndividual:
            self.raisedHandView = nil
        case .remoteInGroup(let callMemberVisualContext):
            switch callMemberVisualContext {
            case .videoGrid, .speaker:
                self.raisedHandView = RaisedHandView(useCompactSize: false)
            case .videoOverflow:
                self.raisedHandView = RaisedHandView(useCompactSize: true)
            }
        }

        super.init(frame: .zero)

        self.addLayoutGuide(layoutGuide)
        layoutGuideConstraints.append(layoutGuide.topAnchor.constraint(equalTo: self.topAnchor, constant: inset))
        layoutGuideConstraints.append(layoutGuide.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -inset))
        layoutGuideConstraints.append(layoutGuide.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: inset))
        layoutGuideConstraints.append(layoutGuide.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -inset))
        NSLayoutConstraint.activate(layoutGuideConstraints)

        muteIndicatorCircleView.isHidden = true
        muteIndicatorCircleView.backgroundColor = .ows_blackAlpha70
        let muteIndicatorImage = UIImageView()
        muteIndicatorImage.setTemplateImageName("mic-slash-fill-28", tintColor: .ows_white)
        muteIndicatorCircleView.addSubview(muteIndicatorImage)
        addSubview(muteIndicatorCircleView)
        muteIndicatorCircleView.autoSetDimension(.height, toSize: Constants.muteImageCircleDimension)
        muteIndicatorCircleView.autoMatch(.width, to: .height, of: muteIndicatorCircleView)
        muteIndicatorImage.autoSetDimension(.height, toSize: Constants.muteImageDimension)
        muteIndicatorImage.autoMatch(.width, to: .height, of: muteIndicatorImage)
        muteIndicatorImage.autoCenterInSuperview()
        NSLayoutConstraint.activate([
            muteIndicatorCircleView.leadingAnchor.constraint(equalTo: self.layoutGuide.leadingAnchor),
            muteIndicatorCircleView.bottomAnchor.constraint(equalTo: self.layoutGuide.bottomAnchor)
        ])

        if let raisedHandView {
            raisedHandView.isHidden = true
            self.addSubview(raisedHandView)
            raisedHandView.autoPinEdge(toSuperviewMargin: .top)
            raisedHandView.autoPinEdge(toSuperviewMargin: .leading)
            raisedHandView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        }

        switch type {
        case .local:
            addSubview(flipCameraButton)
            NSLayoutConstraint.activate([
                flipCameraButton.trailingAnchor.constraint(equalTo: self.layoutGuide.trailingAnchor),
                flipCameraButton.bottomAnchor.constraint(equalTo: self.layoutGuide.bottomAnchor)
            ])
            updateFlipCameraButton()
        case .remoteInGroup, .remoteInIndividual:
            break
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self.flipCameraButton {
            return view
        }
        return nil
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating other elements too.
        self.muteIndicatorCircleView.transform = CGAffineTransform(rotationAngle: rotationAngle)
        updateFlipCameraButton()
        updateLayoutGuideConstraints()
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    ) {
        self.call = call
        updateFlipCameraButton()
        updateMuteIndicatorHiddenState(
            call: call,
            isFullScreen: isFullScreen,
            remoteGroupMemberDeviceState: remoteGroupMemberDeviceState
        )
        updateRaisedHand(
            call: call,
            remoteGroupMemberDeviceState: remoteGroupMemberDeviceState
        )
    }

    func updateDimensions() {
        updateFlipCameraButton()
        updateLayoutGuideConstraints()
    }

    func clearConfiguration() {
        muteIndicatorCircleView.isHidden = true
    }

    // MARK: - General Layout

    private let layoutGuide = UILayoutGuide()
    private var layoutGuideConstraints = [NSLayoutConstraint]()

    enum Constants {
        // For example, for expanded pip on iPhone in 1:1 call.
        fileprivate static let expandedPipMinWidth = CallMemberView.Constants.enlargedPipWidth
        // For example, for non-expanded pip on iPad in group call of 3 members total.
        fileprivate static let mediumPipMinWidth: CGFloat = 72
        fileprivate static let expandedPipInset: CGFloat = 8
        fileprivate static let normalPipInset: CGFloat = 4
        fileprivate static let flipCameraButtonDimensionWhenPipExpanded: CGFloat = 48
        fileprivate static let flipCameraButtonDimensionWhenPipNormal: CGFloat = 28
        fileprivate static let flipCameraImageDimensionWhenPipExpanded: CGFloat = 24
        fileprivate static let flipCameraImageDimensionWhenPipNormal: CGFloat = 16
        fileprivate static let muteImageDimension: CGFloat = 16
        fileprivate static let muteImageCircleDimension: CGFloat = 28
    }

    private var inset: CGFloat {
        return width >= Constants.expandedPipMinWidth ? Constants.expandedPipInset : Constants.normalPipInset
    }

    private func updateLayoutGuideConstraints() {
        self.layoutGuideConstraints.forEach {
            $0.constant = $0.constant/abs($0.constant) * inset
        }
        self.layoutMargins = .init(margin: self.inset)
    }

    // MARK: - Raised hand

    private let raisedHandView: RaisedHandView?
    private func updateRaisedHand(
        call: SignalCall,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    ) {
        guard let raisedHandView else { return }
        guard
            let deviceState = remoteGroupMemberDeviceState,
            case .groupThread(let groupThreadCall) = call.mode,
            deviceState.demuxId != groupThreadCall.ringRtcCall.localDeviceState.demuxId,
            groupThreadCall.raisedHands.contains(deviceState.demuxId),
            !AppEnvironment.shared.windowManagerRef.isCallInPip
        else {
            raisedHandView.isHidden = true
            return
        }

        raisedHandView.name = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)
            if deviceState.aci == localIdentifiers?.aci {
                return CommonStrings.you
            } else {
                return SSKEnvironment.shared.contactManagerRef.displayName(for: deviceState.address, tx: tx).resolvedValue(useShortNameIfAvailable: true)
            }
        }

        raisedHandView.isHidden = false
    }

    private class RaisedHandView: UIStackView {
        private var useCompactSize: Bool
        private var circleSize: CGFloat {
            useCompactSize ? 28 : 40
        }
        private var iconSize: CGFloat {
            useCompactSize ? 16 : 24
        }

        var name: String? {
            didSet {
                nameLabel.text = name
            }
        }

        private let nameLabel = UILabel()

        init(useCompactSize: Bool) {
            self.useCompactSize = useCompactSize
            super.init(frame: .zero)

            self.axis = .horizontal
            self.spacing = 8

            let iconBackground = UIView()
            self.addArrangedSubview(iconBackground)
            iconBackground.autoSetDimensions(to: .square(self.circleSize))
            iconBackground.backgroundColor = .ows_white
            iconBackground.layer.cornerRadius = self.circleSize / 2

            let iconView = UIImageView(image: Theme.iconImage(.raiseHand))
            iconBackground.addSubview(iconView)
            iconView.autoSetDimensions(to: .square(self.iconSize))
            iconView.autoCenterInSuperview()
            iconView.tintColor = .ows_black

            if !useCompactSize {
                self.addArrangedSubview(nameLabel)
                nameLabel.textColor = .ows_white
                nameLabel.font = .dynamicTypeBody2
            }
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    // MARK: - Mute Button

    private let muteIndicatorImage = UIImageView()
    private let muteIndicatorCircleView = CircleView()

    private func updateMuteIndicatorHiddenState(
        call: SignalCall,
        isFullScreen: Bool,
        remoteGroupMemberDeviceState: RemoteDeviceState?
    ) {
        switch type {
        case .local:
            muteIndicatorCircleView.isHidden = !call.isOutgoingAudioMuted || isFullScreen
        case .remoteInGroup(let context):
            muteIndicatorCircleView.isHidden = context == .speaker || remoteGroupMemberDeviceState?.audioMuted != true || isFullScreen
        case .remoteInIndividual:
            muteIndicatorCircleView.isHidden = true
        }
    }

    // MARK: - Flip camera button

    private var flipCameraButtonWidthConstraint: NSLayoutConstraint?
    private var flipCameraImageWidthConstraint: NSLayoutConstraint?

    private lazy var flipCameraCircleView: CircleBlurView = {
        let circleView = CircleBlurView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        circleView.isUserInteractionEnabled = false
        return circleView
    }()

    private lazy var flipCameraImageView = {
        let imageView = UIImageView(image: UIImage(named: "switch-camera-28"))
        imageView.isUserInteractionEnabled = false
        imageView.tintColor = .ows_white
        flipCameraImageWidthConstraint = imageView.autoSetDimension(
            .height,
            toSize: Constants.flipCameraImageDimensionWhenPipNormal
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

        flipCameraButtonWidthConstraint = button.autoSetDimension(
            .height,
            toSize: Constants.flipCameraButtonDimensionWhenPipNormal
        )
        button.autoMatch(.width, to: .height, of: button)
        button.accessibilityLabel = flipCameraButtonAccessibilityLabel
        button.addTarget(self, action: #selector(didPressFlipCamera), for: .touchUpInside)
        flipCameraCircleView.backgroundColor = .ows_blackAlpha70
        button.isHidden = true
        return button
    }()

    @objc
    private func didPressFlipCamera() {
        guard let call else { return }
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

    private func updateFlipCameraButton() {
        switch type {
        case .local:
            break
        case .remoteInGroup, .remoteInIndividual:
            // Flip camera is only for the local user.
            return
        }
        guard let call else { return }
        if width > CallMemberView.Constants.enlargedPipWidthIpadLandscape {
            // This is the widest width the pip can be. If we're wider, it
            // means that the local user is fullscreen (or animating from
            // fullscreen down to the pip) and therefore should
            // not show the flip camera button.
            self.flipCameraButton.isHidden = true
        } else if width >= Constants.expandedPipMinWidth {
            // Pip is expanded or at its regular size for iPad in certain cases.
            self.flipCameraButton.isEnabled = true
            flipCameraCircleView.backgroundColor = .ows_whiteAlpha40
            self.flipCameraButtonWidthConstraint?.constant = Constants.flipCameraButtonDimensionWhenPipExpanded
            self.flipCameraImageWidthConstraint?.constant = Constants.flipCameraImageDimensionWhenPipExpanded
            animateFlipCameraButtonAlphaIfNecessary(
                call: call,
                newIsHidden: call.isOutgoingVideoMuted
            )
        } else if width >= Constants.mediumPipMinWidth {
            flipCameraButton.isEnabled = false
            flipCameraCircleView.backgroundColor = .ows_blackAlpha70
            self.flipCameraButtonWidthConstraint?.constant = Constants.flipCameraButtonDimensionWhenPipNormal
            self.flipCameraImageWidthConstraint?.constant = Constants.flipCameraImageDimensionWhenPipNormal
            animateFlipCameraButtonAlphaIfNecessary(
                call: call,
                newIsHidden: call.isOutgoingVideoMuted
            )
        } else {
            animateFlipCameraButtonAlphaIfNecessary(
                call: call,
                newIsHidden: true
            )
        }
    }

    private func animateFlipCameraButtonAlphaIfNecessary(call: SignalCall, newIsHidden: Bool) {
        guard newIsHidden != self.flipCameraButton.isHidden else { return }
        self.flipCameraButton.alpha = newIsHidden ? 1 : 0
        UIView.animate(withDuration: 0.3, animations: {
            self.flipCameraButton.alpha = newIsHidden ? 0 : 1
            }, completion: { [weak self] _ in
                self?.flipCameraButton.isHidden = newIsHidden
            }
        )
    }

    // MARK: - Required

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
