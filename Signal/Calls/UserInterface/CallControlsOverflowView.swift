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
        picker.isHidden = true
        return picker
    }()

    private var reactionSender: ReactionSender?
    private var reactionsSink: ReactionsSink?

    private weak var emojiPickerSheetPresenter: EmojiPickerSheetPresenter?

    private weak var callControlsOverflowPresenter: CallControlsOverflowPresenter?

    private override init(frame: CGRect) {
        super.init(frame: frame)

        self.addSubview(reactionPicker)
        reactionPicker.autoPinEdgesToSuperviewEdges()

        // TODO: Add Raise Hand button
    }

    convenience init(
        reactionSender: ReactionSender,
        reactionsSink: ReactionsSink,
        emojiPickerSheetPresenter: EmojiPickerSheetPresenter,
        callControlsOverflowPresenter: CallControlsOverflowPresenter
    ) {
        self.init(frame: .zero)
        self.reactionSender = reactionSender
        self.reactionsSink = reactionsSink
        self.emojiPickerSheetPresenter = emojiPickerSheetPresenter
        self.callControlsOverflowPresenter = callControlsOverflowPresenter
    }

    // MARK: - Animations

    private var isAnimating = false

    func animateIn() {
        self.isHidden = false
        guard !isAnimating else {
            return
        }
        isAnimating = true

        self.callControlsOverflowPresenter?.callControlsOverflowWillAppear()

        self.reactionPicker.isHidden = false
        // `playPresentationAnimation` is built to be called on new, rather
        // than reused, reaction pickers. Since we're reusing here, we need
        // to reset the alpha.
        self.reactionPicker.alpha = 1
        self.reactionPicker.playPresentationAnimation(duration: 0.2) { [weak self] in
            self?.isAnimating = false
        }

        // TODO: Animate Raise Hand menu item
    }

    func animateOut() {
        guard !isAnimating else {
            return
        }
        isAnimating = true

        self.reactionPicker.isHidden = true
        self.reactionPicker.playDismissalAnimation(
            duration: 0.2,
            completion: { [weak self] in
                self?.isAnimating = false
                self?.isHidden = true
                self?.callControlsOverflowPresenter?.callControlsOverflowDidDisappear()
            }
        )

        // TODO: Animate Raise Hand menu item
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
            allowReactionConfiguration: false,
            forceDarkTheme: true
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
        self.reactionSender?.react(value: reaction)
        let localAci = databaseStorage.read { tx in
            DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
        }
        guard let localAci else {
            owsFailDebug("Local user is in call but doesn't have ACI!")
            return
        }
        // Locally-sent reactions do not come in via the API, so we add them here.
        self.reactionsSink?.addReactions(
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

// MARK: ReactionSender

protocol ReactionSender {
    func react(value: String)
}

extension GroupCall: ReactionSender {}

// MARK: - EmojiPickerSheetPresenter

protocol EmojiPickerSheetPresenter: AnyObject {
    func present(sheet: EmojiPickerSheet, animated: Bool)
}

extension GroupCallViewController: EmojiPickerSheetPresenter {
    func present(sheet: EmojiPickerSheet, animated: Bool) {
        self.present(sheet, animated: animated)
    }
}

// MARK: - CallControlsOverflowPresenter

protocol CallControlsOverflowPresenter: AnyObject {
    func callControlsOverflowWillAppear()
    func callControlsOverflowDidDisappear()
    func willSendReaction()
}
