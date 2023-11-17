//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import SignalUI

@objc
protocol CallControlsDelegate: AnyObject {
    func didPressHangup(sender: UIButton)
    func didPressAudioSource(sender: UIButton)
    func didPressMute(sender: UIButton)
    func didPressVideo(sender: UIButton)
    func didPressRing(sender: UIButton)
    func didPressFlipCamera(sender: UIButton)
    func didPressJoin(sender: UIButton)
}

class CallControls: UIView {
    private lazy var topStackView = createTopStackView()
    private lazy var hangUpButton: CallButton = {
        let button = createButton(
            iconName: "phone-down-fill-28",
            accessibilityLabel: viewModel.hangUpButtonAccessibilityLabel,
            action: #selector(CallControlsDelegate.didPressHangup)
        )
        button.unselectedBackgroundColor = .ows_accentRed
        return button
    }()
    private(set) lazy var audioSourceButton = createButton(
        iconName: "speaker-fill-28",
        accessibilityLabel: viewModel.audioSourceAccessibilityLabel,
        action: #selector(CallControlsDelegate.didPressAudioSource)
    )
    private lazy var muteButton = createButton(
        iconName: "mic-slash-fill-28",
        accessibilityLabel: viewModel.muteButtonAccessibilityLabel,
        action: #selector(CallControlsDelegate.didPressMute)
    )
    private lazy var videoButton = createButton(
        iconName: "video-fill-28",
        accessibilityLabel: viewModel.videoButtonAccessibilityLabel,
        action: #selector(CallControlsDelegate.didPressVideo)
    )
    private lazy var ringButton = createButton(
        iconName: "bell-ring-fill-28",
        // TODO: Accessibility label
        action: #selector(CallControlsDelegate.didPressRing)
    )
    private lazy var flipCameraButton: CallButton = {
        let button = createButton(
            iconName: "switch-camera-28",
            accessibilityLabel: viewModel.flipCameraButtonAccessibilityLabel,
            action: #selector(CallControlsDelegate.didPressFlipCamera)
        )
        button.selectedIconColor = button.iconColor
        button.selectedBackgroundColor = button.unselectedBackgroundColor
        return button
    }()

    private lazy var joinButtonActivityIndicator = UIActivityIndicatorView(style: .medium)

    private lazy var joinButton: UIButton = {
        let height: CGFloat = 56

        let button = OWSButton()
        button.setTitleColor(.ows_white, for: .normal)
        button.setBackgroundImage(UIImage(color: .ows_accentGreen), for: .normal)
        button.titleLabel?.font = UIFont.dynamicTypeBodyClamped.semibold()
        button.clipsToBounds = true
        button.layer.cornerRadius = height / 2
        button.block = { [weak self, unowned button] in
            self?.delegate.didPressJoin(sender: button)
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 17, leading: 17, bottom: 17, trailing: 17)
        button.addSubview(joinButtonActivityIndicator)
        joinButtonActivityIndicator.autoCenterInSuperview()

        // Expand the button to fit text if necessary.
        button.autoSetDimension(.width, toSize: 168, relation: .greaterThanOrEqual)
        button.autoSetDimension(.height, toSize: height)
        return button
    }()

    private lazy var gradientView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.ows_blackAlpha60.cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    private weak var delegate: CallControlsDelegate!
    private let viewModel: CallControlsViewModel

    init(
        call: SignalCall,
        callService: CallService,
        delegate: CallControlsDelegate
    ) {
        self.viewModel = CallControlsViewModel(call: call, callService: callService)
        self.delegate = delegate
        super.init(frame: .zero)

        viewModel.refreshView = { [weak self] in
            self?.updateControls()
        }

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()

        let joinButtonContainer = UIView()
        joinButtonContainer.addSubview(joinButton)
        joinButtonContainer.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)
        joinButton.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        joinButton.autoPinHeightToSuperview()

        let controlsStack = UIStackView(arrangedSubviews: [
            topStackView,
            joinButtonContainer
        ])
        controlsStack.axis = .vertical
        controlsStack.spacing = 40
        controlsStack.alignment = .center

        addSubview(controlsStack)
        controlsStack.autoPinWidthToSuperview()
        controlsStack.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 40, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh - 1) {
            controlsStack.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 56)
        }
        controlsStack.autoPinEdge(toSuperviewEdge: .top)

        updateControls()
    }

    func createTopStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 16

        stackView.addArrangedSubview(audioSourceButton)
        stackView.addArrangedSubview(flipCameraButton)
        stackView.addArrangedSubview(videoButton)
        stackView.addArrangedSubview(muteButton)
        stackView.addArrangedSubview(ringButton)
        stackView.addArrangedSubview(hangUpButton)

        return stackView
    }

    private func updateControls() {
        // Top row
        audioSourceButton.isHidden = viewModel.audioSourceButtonIsHidden
        hangUpButton.isHidden = viewModel.hangUpButtonIsHidden
        muteButton.isHidden = viewModel.muteButtonIsHidden
        videoButton.isHidden = viewModel.videoButtonIsHidden
        flipCameraButton.isHidden = viewModel.flipCameraButtonIsHidden
        ringButton.isHidden = viewModel.ringButtonIsHidden

        // Bottom row
        joinButton.superview?.isHidden = viewModel.joinButtonIsHidden

        // Sizing and spacing
        let controlCount = topStackView.arrangedSubviews.filter({!$0.isHidden}).count
        topStackView.spacing = viewModel.controlSpacing(controlCount: controlCount)
        let shouldControlButtonsBeSmall = viewModel.shouldControlButtonsBeSmall(controlCount: controlCount)
        for view in topStackView.arrangedSubviews {
            if let button = view as? CallButton {
                button.isSmall = shouldControlButtonsBeSmall
            }
        }

        // Show/hide the superview to adjust the containing stack.
        gradientView.isHidden = viewModel.gradientViewIsHidden

        videoButton.isSelected = viewModel.videoButtonIsSelected
        muteButton.isSelected = viewModel.muteButtonIsSelected

        if !viewModel.audioSourceButtonIsHidden {
            let config = viewModel.audioSourceButtonConfiguration
            audioSourceButton.showDropdownArrow = config.showDropdownArrow
            audioSourceButton.iconName = config.iconName
        }

        if
            !viewModel.ringButtonIsHidden,
            let ringButtonConfig = viewModel.ringButtonConfiguration
        {
            ringButton.isUserInteractionEnabled = ringButtonConfig.isUserInteractionEnabled
            ringButton.isSelected = ringButtonConfig.isSelected
            ringButton.shouldDrawAsDisabled = ringButtonConfig.shouldDrawAsDisabled
        }

        if !viewModel.joinButtonIsHidden {
            let joinButtonConfig = viewModel.joinButtonConfig
            joinButton.setTitle(joinButtonConfig.label, for: .normal)
            joinButton.setTitleColor(joinButtonConfig.color, for: .normal)
            joinButton.adjustsImageWhenHighlighted = joinButtonConfig.adjustsImageWhenHighlighted
            joinButton.isUserInteractionEnabled = joinButtonConfig.isUserInteractionEnabled
            if viewModel.shouldJoinButtonActivityIndicatorBeAnimating {
                joinButtonActivityIndicator.startAnimating()
            } else {
                joinButtonActivityIndicator.stopAnimating()
            }
        }

        hangUpButton.accessibilityLabel = viewModel.hangUpButtonAccessibilityLabel
        audioSourceButton.accessibilityLabel = viewModel.audioSourceAccessibilityLabel
        muteButton.accessibilityLabel = viewModel.muteButtonAccessibilityLabel
        videoButton.accessibilityLabel = viewModel.videoButtonAccessibilityLabel
        flipCameraButton.accessibilityLabel = viewModel.flipCameraButtonAccessibilityLabel
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createButton(iconName: String, accessibilityLabel: String? = nil, action: Selector) -> CallButton {
        let button = CallButton(iconName: iconName)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(delegate, action: action, for: .touchUpInside)
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalLow()
        button.alpha = 0.9
        return button
    }
}

private class CallControlsViewModel {
    private let call: SignalCall
    private let callService: CallService
    fileprivate var refreshView: (() -> Void)?
    init(call: SignalCall, callService: CallService) {
        self.call = call
        self.callService = callService
        call.addObserverAndSyncState(observer: self)
        callService.audioService.delegate = self
    }

    deinit {
        call.removeObserver(self)
        callService.audioService.delegate = nil
    }

    private var hasExternalAudioInputsAndAudioSource: Bool {
        let audioService = callService.audioService
        return audioService.hasExternalInputs && audioService.currentAudioSource != nil
    }

    var audioSourceButtonIsHidden: Bool {
        if hasExternalAudioInputsAndAudioSource {
            return false
        } else if UIDevice.current.isIPad {
            // iPad *only* supports speaker mode, if there are no external
            // devices connected, so we don't need to show the button unless
            // we have alternate audio sources.
            return true
        } else {
            return !call.isOutgoingVideoMuted
        }
    }

    struct AudioSourceButtonConfiguration {
        let showDropdownArrow: Bool
        let iconName: String
    }

    var audioSourceButtonConfiguration: AudioSourceButtonConfiguration {
        let showDropdownArrow: Bool
        let iconName: String
        if
            callService.audioService.hasExternalInputs,
            let audioSource = callService.audioService.currentAudioSource
        {
            showDropdownArrow = true
            if audioSource.isBuiltInEarPiece {
                iconName = "phone-fill-28"
            } else if audioSource.isBuiltInSpeaker {
                iconName = "speaker-fill-28"
            } else {
                iconName = "speaker-bt-fill-28"
            }
        } else {
            // No bluetooth audio detected
            showDropdownArrow = false
            iconName = "speaker-fill-28"
        }
        return AudioSourceButtonConfiguration(showDropdownArrow: showDropdownArrow, iconName: iconName)
    }

    var hangUpButtonIsHidden: Bool {
        switch call.mode {
        case .individual(_):
            return false
        case .group(_):
            return call.joinState != .joined
        }
    }

    var muteButtonIsHidden: Bool {
        return false
    }

    var videoButtonIsHidden: Bool {
        return false
    }

    var flipCameraButtonIsHidden: Bool {
        return call.isOutgoingVideoMuted
    }

    var joinButtonIsHidden: Bool {
        switch call.mode {
        case .individual(_):
            // TODO: Introduce lobby for starting 1:1 video calls.
            return true
        case .group(let call):
            return call.localDeviceState.joinState == .joined
        }
    }

    struct JoinButtonConfiguration {
        let label: String
        let color: UIColor
        let adjustsImageWhenHighlighted: Bool
        let isUserInteractionEnabled: Bool
    }

    var joinButtonConfig: JoinButtonConfiguration {
        if !call.canJoin {
            // Make the button look disabled, but don't actually disable it.
            // We want to show a toast if the user taps anyway.
            return JoinButtonConfiguration(
                label: OWSLocalizedString(
                    "GROUP_CALL_IS_FULL",
                    comment: "Text explaining the group call is full"
                ),
                color: .ows_whiteAlpha40,
                adjustsImageWhenHighlighted: false,
                isUserInteractionEnabled: true
            )
        } else if call.joinState == .joining || call.joinState == .pending {
            return JoinButtonConfiguration(
                label: "",
                color: .ows_whiteAlpha40,
                adjustsImageWhenHighlighted: false,
                isUserInteractionEnabled: false
            )
        } else {
            let startCallText = OWSLocalizedString(
                "CALL_START_BUTTON",
                comment: "Button to start a call"
            )
            let label: String
            switch call.mode {
            case .individual(_):
                // We only show a lobby for 1:1 calls when the call is being initiated.
                // TODO: The work of adding the lobby for 1:1 calls in the unified call view
                // controller (currently GroupCallViewController) is not yet complete.
                label = startCallText
            case .group(_):
                let joinCallText = OWSLocalizedString(
                    "GROUP_CALL_JOIN_BUTTON",
                    comment: "Button to join an ongoing group call"
                )
                label = call.ringRestrictions.contains(.callInProgress) ? joinCallText : startCallText
            }
            return JoinButtonConfiguration(
                label: label,
                color: .white,
                adjustsImageWhenHighlighted: true,
                isUserInteractionEnabled: true
            )
        }
    }

    var shouldJoinButtonActivityIndicatorBeAnimating: Bool {
        return (call.joinState == .joining || call.joinState == .pending) && !joinButtonIsHidden
    }

    var ringButtonIsHidden: Bool {
        switch call.mode {
        case .individual(_):
            return true
        case .group(_):
            return call.joinState == .joined || call.ringRestrictions.intersects([.notApplicable, .callInProgress])
        }
    }

    struct RingButtonConfiguration {
        let isUserInteractionEnabled: Bool
        let isSelected: Bool
        let shouldDrawAsDisabled: Bool
    }

    var ringButtonConfiguration: RingButtonConfiguration? {
        switch call.mode {
        case .individual(_):
            // We never show the ring button for 1:1 calls.
            return nil
        case .group(_):
            // Leave the button visible but locked if joining, like the "join call" button.
            let isUserInteractionEnabled = call.joinState == .notJoined
            let isSelected: Bool
            if
                call.ringRestrictions.isEmpty,
                case .shouldRing = call.groupCallRingState
            {
                isSelected = true
            } else {
                isSelected = false
            }
            // Leave the button enabled so we can present an explanatory toast, but show it disabled.
            let shouldDrawAsDisabled = !call.ringRestrictions.isEmpty
            return RingButtonConfiguration(
                isUserInteractionEnabled: isUserInteractionEnabled,
                isSelected: isSelected,
                shouldDrawAsDisabled: shouldDrawAsDisabled
            )
        }
    }

    var gradientViewIsHidden: Bool {
        return call.joinState != .joined
    }

    var videoButtonIsSelected: Bool {
        return !call.isOutgoingVideoMuted
    }

    var muteButtonIsSelected: Bool {
        return call.isOutgoingAudioMuted
    }

    func controlSpacing(controlCount: Int) -> CGFloat {
        return (UIDevice.current.isNarrowerThanIPhone6 && controlCount > 4) ? 12 : 16
    }

    func shouldControlButtonsBeSmall(controlCount: Int) -> Bool {
        return UIDevice.current.isIPad ? false : controlCount > 4
    }
}

extension CallControlsViewModel: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        refreshView?()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        refreshView?()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        refreshView?()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        refreshView?()
    }

    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {
        refreshView?()
    }

    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        refreshView?()
    }

    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {
        refreshView?()
    }

    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {
        refreshView?()
    }

    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {
        refreshView?()
    }

    func individualCallRemoteSharingScreenDidChange(_ call: SignalCall, isRemoteSharingScreen: Bool) {
        refreshView?()
    }
}

extension CallControlsViewModel: CallAudioServiceDelegate {
    func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService) {
        refreshView?()
    }

    func callAudioServiceDidChangeAudioSource(_ callAudioService: CallAudioService, audioSource: AudioSource?) {
        refreshView?()
    }
}

// MARK: - Accessibility

extension CallControlsViewModel {
    public var hangUpButtonAccessibilityLabel: String {
        switch call.mode {
        case .individual(_):
            return OWSLocalizedString(
                "CALL_VIEW_HANGUP_LABEL",
                comment: "Accessibility label for hang up call"
            )
        case .group(_):
            return OWSLocalizedString(
                "CALL_VIEW_LEAVE_CALL_LABEL",
                comment: "Accessibility label for leaving a call"
            )
        }
    }

    public var audioSourceAccessibilityLabel: String {
        // TODO: This is not the most helpful descriptor.
        return OWSLocalizedString(
            "CALL_VIEW_AUDIO_SOURCE_LABEL",
            comment: "Accessibility label for selection the audio source"
        )
    }

    public var muteButtonAccessibilityLabel: String {
        if call.isOutgoingAudioMuted {
            return OWSLocalizedString(
                "CALL_VIEW_UNMUTE_LABEL",
                comment: "Accessibility label for unmuting the microphone"
            )
        } else {
            return OWSLocalizedString(
                "CALL_VIEW_MUTE_LABEL",
                comment: "Accessibility label for muting the microphone"
            )
        }
    }

    public var videoButtonAccessibilityLabel: String {
        if call.isOutgoingVideoMuted {
            return OWSLocalizedString(
                "CALL_VIEW_TURN_VIDEO_ON_LABEL",
                comment: "Accessibility label for turning on the camera"
            )
        } else {
            return OWSLocalizedString(
                "CALL_VIEW_TURN_VIDEO_OFF_LABEL",
                comment: "Accessibility label for turning off the camera"
            )
        }
    }

    public var flipCameraButtonAccessibilityLabel: String {
        return OWSLocalizedString(
            "CALL_VIEW_SWITCH_CAMERA_DIRECTION",
            comment: "Accessibility label to toggle front- vs. rear-facing camera"
        )
    }
}
