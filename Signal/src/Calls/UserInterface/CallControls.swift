//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit

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
    private lazy var ringButton = createButton(
        iconName: "ring-28",
        action: #selector(CallControlsDelegate.didPressRing)
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

    private lazy var joinButtonActivityIndicator = UIActivityIndicatorView(style: .white)

    private lazy var joinButton: UIButton = {
        let height: CGFloat = 56

        let button = OWSButton()
        button.setTitleColor(.ows_white, for: .normal)
        button.setBackgroundImage(UIImage(color: .ows_accentGreen), for: .normal)
        button.titleLabel?.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
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

    private lazy var topStackView = createTopStackView()

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

        let joinButtonContainer = UIView()
        joinButtonContainer.addSubview(joinButton)
        joinButtonContainer.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)
        joinButton.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        joinButton.autoPinHeightToSuperview()

        let controlsStack = UIStackView(arrangedSubviews: [topStackView, joinButtonContainer])
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

    deinit {
        call.removeObserver(self)
        callService.audioService.delegate = nil
    }

    func createTopStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 16

        stackView.addArrangedSubview(audioSourceButton)
        stackView.addArrangedSubview(flipCameraButton)
        stackView.addArrangedSubview(muteButton)
        stackView.addArrangedSubview(videoButton)
        stackView.addArrangedSubview(ringButton)
        stackView.addArrangedSubview(hangUpButton)

        return stackView
    }

    private func updateControls() {
        let hasExternalAudioInputs = callService.audioService.hasExternalInputs
        let isLocalVideoMuted = call.groupCall.isOutgoingVideoMuted
        let joinState = call.groupCall.localDeviceState.joinState

        flipCameraButton.isHidden = isLocalVideoMuted
        videoButton.isSelected = !isLocalVideoMuted
        muteButton.isSelected = call.groupCall.isOutgoingAudioMuted

        ringButton.isHidden = joinState == .joined || call.ringRestrictions.intersects([.notApplicable, .callInProgress])
        // Leave the button visible but locked if joining, like the "join call" button.
        ringButton.isUserInteractionEnabled = joinState == .notJoined
        if call.ringRestrictions.isEmpty, case .shouldRing = call.groupCallRingState {
            ringButton.isSelected = true
        } else {
            ringButton.isSelected = false
        }
        // Leave the button enabled so we can present an explanatory toast, but show it disabled.
        ringButton.shouldDrawAsDisabled = !call.ringRestrictions.isEmpty

        hangUpButton.isHidden = joinState != .joined

        if !UIDevice.current.isIPad {
            // Use small controls if video is enabled and we have external
            // audio inputs, because we have five buttons now.
            [audioSourceButton, flipCameraButton, videoButton, muteButton, ringButton, hangUpButton].forEach {
                let isSmall = hasExternalAudioInputs && !isLocalVideoMuted
                $0.isSmall = isSmall
                if UIDevice.current.isNarrowerThanIPhone6 {
                    topStackView.spacing = isSmall ? 12 : 16
                }
            }
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

        // Show/hide the superview to adjust the containing stack.
        joinButton.superview?.isHidden = joinState == .joined
        gradientView.isHidden = joinState != .joined

        if call.groupCall.isFull {
            // Make the button look disabled, but don't actually disable it.
            // We want to show a toast if the user taps anyway.
            joinButton.setTitleColor(.ows_whiteAlpha40, for: .normal)
            joinButton.adjustsImageWhenHighlighted = false

            joinButton.setTitle(
                NSLocalizedString(
                    "GROUP_CALL_IS_FULL",
                    comment: "Text explaining the group call is full"),
                for: .normal)

        } else if joinState == .joining {
            joinButton.isUserInteractionEnabled = false
            joinButtonActivityIndicator.startAnimating()

            joinButton.setTitle("", for: .normal)

        } else {
            joinButton.setTitleColor(.white, for: .normal)
            joinButton.adjustsImageWhenHighlighted = true
            joinButton.isUserInteractionEnabled = true
            joinButtonActivityIndicator.stopAnimating()

            let startCallText = NSLocalizedString("GROUP_CALL_START_BUTTON", comment: "Button to start a group call")
            let joinCallText = NSLocalizedString("GROUP_CALL_JOIN_BUTTON", comment: "Button to join an ongoing group call")

            joinButton.setTitle(call.ringRestrictions.contains(.callInProgress) ? joinCallText : startCallText,
                                for: .normal)
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
