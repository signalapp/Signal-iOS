//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit

class CallControlsOverflowView: UIView {
    private lazy var reactionPicker: MessageReactionPicker = {
        let picker = MessageReactionPicker(
            selectedEmoji: nil,
            delegate: self,
            style: .contextMenu,
            forceDarkTheme: true
        )
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true
        return picker
    }()

    private class ButtonStack: UIStackView {
        private let raiseHandLabel: UILabel
        let raiseHandButton: UIButton

        var isHandRaised: Bool {
            didSet {
                if isHandRaised {
                    self.raiseHandLabel.text =  OWSLocalizedString(
                        "CALL_LOWER_HAND_BUTTON_LABEL",
                        comment: "Label on button for lowering hand in call."
                    )
                } else {
                    self.raiseHandLabel.text =  OWSLocalizedString(
                        "CALL_RAISE_HAND_BUTTON_LABEL",
                        comment: "Label on button for raising hand in call."
                    )
                }
            }
        }

        init() {
            self.raiseHandLabel = UILabel()
            self.raiseHandLabel.translatesAutoresizingMaskIntoConstraints = false
            self.raiseHandLabel.textColor = .white

            let icon = UIImageView(image: .init(named: "raise_hand"))
            icon.tintColor = .white
            icon.translatesAutoresizingMaskIntoConstraints = false

            let raiseHandInteriorView = UIView()
            raiseHandInteriorView.isUserInteractionEnabled = false
            raiseHandInteriorView.addSubview(self.raiseHandLabel)
            raiseHandInteriorView.addSubview(icon)
            NSLayoutConstraint.activate([
                self.raiseHandLabel.leadingAnchor.constraint(equalTo: raiseHandInteriorView.leadingAnchor, constant: Constants.buttonHInset),
                self.raiseHandLabel.topAnchor.constraint(equalTo: raiseHandInteriorView.topAnchor, constant: Constants.buttonVInset),
                self.raiseHandLabel.bottomAnchor.constraint(equalTo: raiseHandInteriorView.bottomAnchor, constant: -Constants.buttonVInset),
                self.raiseHandLabel.trailingAnchor.constraint(lessThanOrEqualTo: icon.leadingAnchor),
                icon.widthAnchor.constraint(equalToConstant: Constants.iconDimension),
                icon.heightAnchor.constraint(equalToConstant: Constants.iconDimension),
                icon.trailingAnchor.constraint(equalTo: raiseHandInteriorView.trailingAnchor, constant: -Constants.buttonHInset),
                icon.centerYAnchor.constraint(equalTo: raiseHandInteriorView.centerYAnchor),
            ])
            raiseHandInteriorView.translatesAutoresizingMaskIntoConstraints = false

            self.raiseHandButton = UIButton()
            self.raiseHandButton.addSubview(raiseHandInteriorView)
            raiseHandInteriorView.autoPinEdgesToSuperviewEdges()
            self.raiseHandButton.translatesAutoresizingMaskIntoConstraints = false

            self.isHandRaised = false

            super.init(frame: .zero)
            self.addArrangedSubviews([self.raiseHandButton])
            self.translatesAutoresizingMaskIntoConstraints = false
            self.axis = .vertical
            self.layer.cornerRadius = Constants.stackViewCornerRadius
            self.isHidden = true

            let backgroundView = self.addBackgroundView(
                withBackgroundColor: .ows_gray75,
                cornerRadius: Constants.stackViewCornerRadius
            )
            backgroundView.layer.shadowColor = UIColor.ows_black.cgColor
            backgroundView.layer.shadowRadius = Constants.stackViewBackgroundViewShadowRadius
            backgroundView.layer.shadowOpacity = Constants.stackViewBackgroundViewShadowOpacity
            backgroundView.layer.shadowOffset = .zero

            let shadowView = UIView()
            shadowView.backgroundColor = .ows_gray75
            shadowView.layer.cornerRadius = Constants.stackViewCornerRadius
            shadowView.layer.shadowColor = UIColor.ows_black.cgColor
            shadowView.layer.shadowRadius = Constants.stackViewShadowRadius
            shadowView.layer.shadowOpacity = Constants.stackViewShadowOpacity
            shadowView.layer.shadowOffset = Constants.stackViewShadowOffset
            backgroundView.addSubview(shadowView)
            shadowView.autoPinEdgesToSuperviewEdges()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private lazy var buttonStack = ButtonStack()

    private var reactionSender: ReactionSender
    private var reactionsSink: ReactionsSink

    private var raiseHandSender: RaiseHandSender
    private var call: SignalCall

    private weak var emojiPickerSheetPresenter: EmojiPickerSheetPresenter?

    private weak var callControlsOverflowPresenter: CallControlsOverflowPresenter?

    init(
        call: SignalCall,
        reactionSender: ReactionSender,
        reactionsSink: ReactionsSink,
        raiseHandSender: RaiseHandSender,
        emojiPickerSheetPresenter: EmojiPickerSheetPresenter,
        callControlsOverflowPresenter: CallControlsOverflowPresenter
    ) {
        self.call = call
        self.reactionSender = reactionSender
        self.reactionsSink = reactionsSink
        self.raiseHandSender = raiseHandSender
        self.emojiPickerSheetPresenter = emojiPickerSheetPresenter
        self.callControlsOverflowPresenter = callControlsOverflowPresenter

        super.init(frame: .zero)

        self.addSubview(reactionPicker)
        NSLayoutConstraint.activate([
            reactionPicker.topAnchor.constraint(equalTo: self.topAnchor),
            reactionPicker.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            reactionPicker.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])

        self.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: reactionPicker.bottomAnchor, constant: Constants.spacingBetweenEmojiPickerAndStackView),
            buttonStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        buttonStack.raiseHandButton.addTarget(self, action: #selector(CallControlsOverflowView.didTapRaiseHandButton), for: .touchUpInside)
    }

    // MARK: - Constants

    private enum Constants {
        static let animationDuration = 0.2
        static let buttonHInset: CGFloat = 16
        static let buttonVInset: CGFloat = 12
        static let iconDimension: CGFloat = 22
        static let stackViewCornerRadius: CGFloat = 12
        static let spacingBetweenEmojiPickerAndStackView: CGFloat = 10
        static let stackViewShadowRadius: CGFloat = 28
        static let stackViewBackgroundViewShadowRadius: CGFloat = 4
        static let stackViewShadowOpacity: Float = 0.3
        static let stackViewBackgroundViewShadowOpacity: Float = 0.05
        static let stackViewShadowOffset = CGSize(width: 0, height: 4)

    }

    // MARK: - Animations

    private(set) var isAnimating = false

    func animateIn() {
        self.buttonStack.isHandRaised = self.isLocalHandRaised

        self.isHidden = false
        guard !isAnimating else {
            return
        }
        isAnimating = true

        self.callControlsOverflowPresenter?.callControlsOverflowWillAppear()

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.isAnimating = false
        }
        self.reactionPicker.isHidden = false
        // `playPresentationAnimation` is built to be called on new, rather
        // than reused, reaction pickers. Since we're reusing here, we need
        // to reset the alpha.
        self.reactionPicker.alpha = 1
        self.reactionPicker.playPresentationAnimation(duration: Constants.animationDuration)

        buttonStack.isHidden = false
        buttonStack.alpha = 0
        UIView.animate(withDuration: Constants.animationDuration) { [buttonStack] in
            buttonStack.alpha = 1
        }
        CATransaction.commit()
    }

    func animateOut() {
        guard !isAnimating else {
            return
        }
        isAnimating = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.isAnimating = false
            self.isHidden = true
        }
        self.reactionPicker.playDismissalAnimation(
            duration: Constants.animationDuration,
            completion: { [weak self] in
                self?.callControlsOverflowPresenter?.callControlsOverflowDidDisappear()
            }
        )
        buttonStack.alpha = 1
        buttonStack.backgroundColor = .ows_gray75
        UIView.animate(withDuration: Constants.animationDuration) { [buttonStack] in
            buttonStack.alpha = 0
        } completion: { [buttonStack] _ in
            buttonStack.isHidden = true
        }
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageReactionPickerDelegate

extension CallControlsOverflowView: MessageReactionPickerDelegate {
    func didSelectReaction(reaction: String, isRemoving: Bool, inPosition position: Int) {
        self.react(with: reaction)
    }

    func didSelectAnyEmoji() {
        let sheet = EmojiPickerSheet(
            message: nil,
            forceDarkTheme: true,
            reactionPickerConfigurationListener: self
        ) { [weak self] selectedEmoji in
            guard let selectedEmoji else { return }
            self?.react(with: selectedEmoji.rawValue)
        }
        emojiPickerSheetPresenter?.present(
            sheet: sheet,
            animated: true
        )
    }

    private func react(with reaction: String) {
        self.callControlsOverflowPresenter?.willSendReaction()
        self.reactionSender.react(value: reaction)
        let localAci = SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
        }
        guard let localAci else {
            owsFailDebug("Local user is in call but doesn't have ACI!")
            return
        }
        // Locally-sent reactions do not come in via the API, so we add them here.
        self.reactionsSink.addReactions(
            reactions: [
                Reaction(
                    emoji: reaction,
                    name: CommonStrings.you,
                    aci: localAci,
                    timestamp: Date.timeIntervalSinceReferenceDate
                )
            ]
        )
    }
}

// Reaction Configuration Updates

extension CallControlsOverflowView: ReactionPickerConfigurationListener {
    func didCompleteReactionPickerConfiguration() {
        self.reactionPicker.updateReactionPickerEmojis()
    }
}

// MARK: ReactionSender

protocol ReactionSender {
    @MainActor
    func react(value: String)
}

extension SignalRingRTC.GroupCall: ReactionSender {}

// MARK: - EmojiPickerSheetPresenter

protocol EmojiPickerSheetPresenter: AnyObject {
    func present(sheet: EmojiPickerSheet, animated: Bool)
}

extension GroupCallViewController: EmojiPickerSheetPresenter {
    func present(sheet: EmojiPickerSheet, animated: Bool) {
        self.present(sheet, animated: animated)
    }
}

// MARK: Raise Hand Button

protocol RaiseHandSender {
    @MainActor
    func raiseHand(raise: Bool)
}

extension SignalRingRTC.GroupCall: RaiseHandSender {}

extension CallControlsOverflowView {
    @objc
    private func didTapRaiseHandButton() {
        self.callControlsOverflowPresenter?.didTapRaiseOrLowerHand()
        self.raiseHandSender.raiseHand(raise: !self.isLocalHandRaised)
    }

    private var isLocalHandRaised: Bool {
        switch self.call.mode {
        case .individual:
            owsFailDebug("You shouldn't be able to raise your hand in a 1:1 call.")
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            if let localDemuxId = call.ringRtcCall.localDeviceState.demuxId {
                return call.raisedHands.contains(localDemuxId)
            }
        }
        return false
    }
}

// MARK: - CallControlsOverflowPresenter

protocol CallControlsOverflowPresenter: AnyObject {
    func callControlsOverflowWillAppear()
    func callControlsOverflowDidDisappear()
    func willSendReaction()
    func didTapRaiseOrLowerHand()
}
