//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

@objc
protocol CallControlsDelegate: class {
    func didPressHangup(sender: UIButton)
    func didPressAudioSource(sender: UIButton)
    func didPressMute(sender: UIButton)
    func didPressVideo(sender: UIButton)
    func didPressFlipCamera(sender: UIButton)
    func didPressCancel(sender: UIButton)
    func didPressJoin(sender: UIButton)
}

class CallControls: UIView {
    private lazy var hangUpButton: CallButton = {
        let button = createButton(
            iconName: "phone-down-solid-28",
            action: #selector(CallControlsDelegate.didPressHangup)
        )
        button.unselectedBackgroundColor = .ows_accentRed
        return button
    }()
    private(set) lazy var audioSourceButton = createButton(
        iconName: "speaker-solid-28",
        action: #selector(CallControlsDelegate.didPressAudioSource)
    )
    private lazy var muteButton = createButton(
        iconName: "mic-off-solid-28",
        action: #selector(CallControlsDelegate.didPressMute)
    )
    private lazy var videoButton = createButton(
        iconName: "video-solid-28",
        action: #selector(CallControlsDelegate.didPressVideo)
    )
    private lazy var flipCameraButton: CallButton = {
        let button = createButton(
            iconName: "switch-camera-28",
            action: #selector(CallControlsDelegate.didPressFlipCamera)
        )
        button.selectedIconColor = button.iconColor
        button.selectedBackgroundColor = button.unselectedBackgroundColor
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = OWSButton()
        button.setTitle(CommonStrings.cancelButton, for: .normal)
        button.setTitleColor(.ows_white, for: .normal)
        button.setBackgroundImage(UIImage(color: .ows_whiteAlpha40), for: .normal)
        button.titleLabel?.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        button.clipsToBounds = true
        button.layer.cornerRadius = 8
        button.block = { [weak self] in
            self?.delegate.didPressCancel(sender: button)
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11)
        return button
    }()

    private lazy var joinButtonActivityIndicator = UIActivityIndicatorView(style: .white)

    private lazy var joinButton: UIButton = {
        let button = OWSButton()
        button.setTitleColor(.ows_white, for: .normal)
        button.setBackgroundImage(UIImage(color: .ows_accentGreen), for: .normal)
        button.titleLabel?.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        button.clipsToBounds = true
        button.layer.cornerRadius = 8
        button.block = { [weak self] in
            self?.delegate.didPressJoin(sender: button)
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11)
        button.addSubview(joinButtonActivityIndicator)
        button.setTitle(
            NSLocalizedString(
                "GROUP_CALL_IS_FULL",
                comment: "Text explaining the group call is full"
            ),
            for: .disabled
        )
        button.setTitleColor(.ows_whiteAlpha40, for: .disabled)
        joinButtonActivityIndicator.autoCenterInSuperview()
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

    private lazy var topStackView = createTopStackView()
    private lazy var bottomStackView = createBottomStackView()

    private weak var delegate: CallControlsDelegate!
    private let call: SignalCall

    init(call: SignalCall, delegate: CallControlsDelegate) {
        self.call = call
        self.delegate = delegate
        super.init(frame: .zero)

        call.addObserverAndSyncState(observer: self)

        callService.audioService.delegate = self

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()

        let controlsStack = UIStackView(arrangedSubviews: [topStackView, bottomStackView])
        controlsStack.axis = .vertical
        controlsStack.spacing = 40

        addSubview(controlsStack)
        controlsStack.autoPinWidthToSuperview()
        controlsStack.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 24)
        controlsStack.autoPinEdge(toSuperviewEdge: .top, withInset: 22)

        updateControls()
    }

    deinit {
        call.removeObserver(self)
        callService.audioService.delegate = nil
    }

    func createTopStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 16

        let leadingSpacer = UIView.hStretchingSpacer()
        let trailingSpacer = UIView.hStretchingSpacer()

        stackView.addArrangedSubview(leadingSpacer)
        stackView.addArrangedSubview(audioSourceButton)
        stackView.addArrangedSubview(flipCameraButton)
        stackView.addArrangedSubview(muteButton)
        stackView.addArrangedSubview(videoButton)
        stackView.addArrangedSubview(hangUpButton)
        stackView.addArrangedSubview(trailingSpacer)

        leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

        return stackView
    }

    func createBottomStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8

        let leadingSpacer = UIView.hStretchingSpacer()
        let trailingSpacer = UIView.hStretchingSpacer()

        stackView.addArrangedSubview(leadingSpacer)
        stackView.addArrangedSubview(cancelButton)
        stackView.addArrangedSubview(joinButton)
        stackView.addArrangedSubview(trailingSpacer)

        // Prefer to be big.
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            cancelButton.autoSetDimension(.width, toSize: 170)
        }

        cancelButton.autoMatch(.width, to: .width, of: joinButton)
        leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        leadingSpacer.autoSetDimension(.width, toSize: 16, relation: .greaterThanOrEqual)

        return stackView
    }

    private func updateControls() {
        let hasExternalAudioInputs = callService.audioService.hasExternalInputs
        let isLocalVideoMuted = call.groupCall.isOutgoingVideoMuted

        flipCameraButton.isHidden = isLocalVideoMuted
        videoButton.isSelected = !isLocalVideoMuted
        muteButton.isSelected = call.groupCall.isOutgoingAudioMuted
        hangUpButton.isHidden = call.groupCall.localDeviceState.joinState != .joined

        // Use small controls if video is enabled and we have external
        // audio inputs, because we have five buttons now.
        [audioSourceButton, flipCameraButton, videoButton, muteButton, hangUpButton].forEach {
            $0.isSmall = hasExternalAudioInputs && !isLocalVideoMuted
        }

        // Audio Source Handling
        if hasExternalAudioInputs, let audioSource = callService.audioService.currentAudioSource {
            audioSourceButton.showDropdownArrow = true
            audioSourceButton.isHidden = false

            if audioSource.isBuiltInEarPiece {
                audioSourceButton.iconName = "phone-solid-28"
            } else if audioSource.isBuiltInSpeaker {
                audioSourceButton.iconName = "speaker-solid-28"
            } else {
                audioSourceButton.iconName = "speaker-bt-solid-28"
            }
        } else if UIDevice.current.isIPad {
            // iPad *only* supports speaker mode, if there are no external
            // devices connected, so we don't need to show the button unless
            // we have alternate audio sources.
            audioSourceButton.isHidden = true
        } else {
            // If there are no external audio sources, and video is enabled,
            // speaker mode is always enabled so we don't need to show the button.
            audioSourceButton.isHidden = !isLocalVideoMuted

            // No bluetooth audio detected
            audioSourceButton.iconName = "speaker-solid-28"
            audioSourceButton.showDropdownArrow = false
        }

        bottomStackView.isHidden = call.groupCall.localDeviceState.joinState == .joined

        let startCallText = NSLocalizedString("GROUP_CALL_START_BUTTON", comment: "Button to start a group call")
        let joinCallText = NSLocalizedString("GROUP_CALL_JOIN_BUTTON", comment: "Button to join an ongoing group call")

        if call.groupCall.isFull {
            joinButton.isEnabled = false
        } else if call.groupCall.localDeviceState.joinState == .joining {
            joinButton.isEnabled = true
            joinButton.isUserInteractionEnabled = false
            joinButtonActivityIndicator.startAnimating()

            joinButton.setTitle("", for: .normal)
        } else {
            joinButton.isEnabled = true
            joinButton.isUserInteractionEnabled = true
            joinButtonActivityIndicator.stopAnimating()

            let deviceCount = call.groupCall.peekInfo?.deviceCount ?? 0
            joinButton.setTitle(deviceCount == 0 ? startCallText : joinCallText, for: .normal)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createButton(iconName: String, action: Selector) -> CallButton {
        let button = CallButton(iconName: iconName)
        button.addTarget(delegate, action: action, for: .touchUpInside)
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalLow()
        button.alpha = 0.9
        return button
    }
}

extension CallControls: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)
        updateControls()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        updateControls()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        updateControls()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        updateControls()
    }
}

extension CallControls: CallAudioServiceDelegate {
    func callAudioServiceDidChangeAudioSession(_ callAudioService: CallAudioService) {
        updateControls()
    }

    func callAudioServiceDidChangeAudioSource(_ callAudioService: CallAudioService, audioSource: AudioSource?) {
        updateControls()
    }
}
