//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

protocol ReactionPickerConfigurationListener {
    func didCompleteReactionPickerConfiguration()
}

public class CustomReactionPickerConfigViewController: UIViewController {

    private lazy var reactionPicker = MessageReactionPicker(
        selectedReaction: nil,
        delegate: nil,
        style: .configure,
    )

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString("TAP_REPLACE_EMOJI", comment: "Tap to Replace Emoji string for reaction configuration")
        label.font = UIFont.dynamicTypeSubheadline
        label.textColor = UIColor.Signal.secondaryLabel
        return label
    }()

    private let reactionPickerConfigurationListener: ReactionPickerConfigurationListener?

    init(
        reactionPickerConfigurationListener: ReactionPickerConfigurationListener? = nil,
    ) {
        self.reactionPickerConfigurationListener = reactionPickerConfigurationListener
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString("CONFIGURE_REACTIONS", comment: "Configure reactions title text")
        view.backgroundColor = .Signal.tertiaryGroupedBackground

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.doneButtonTapped()
        }

        navigationItem.leftBarButtonItem = .button(
            title: OWSLocalizedString(
                "RESET",
                comment: "Configure reactions reset button text",
            ),
            style: .plain,
            action: { [weak self] in
                self?.resetButtonTapped()
            },
        )

        // Reaction picker
        reactionPicker.delegate = self
        view.addSubview(reactionPicker)
        reactionPicker.autoHCenterInSuperview()
        reactionPicker.autoPinEdge(toSuperviewMargin: .top, withInset: 95)

        view.addSubview(instructionLabel)
        instructionLabel.autoHCenterInSuperview()
        instructionLabel.autoPinEdge(.top, to: .bottom, of: reactionPicker, withOffset: 30)
    }

    private func resetButtonTapped() {
        let defaultReactions = ReactionManager.defaultCustomReactionSet

        for (index, item) in reactionPicker.currentReactionItems().enumerated() {
            if let newReaction = defaultReactions[safe: index] {
                reactionPicker.replaceReaction(
                    item,
                    new: newReaction,
                    inPosition: index
                )
            }
        }
    }

    private func doneButtonTapped() {
        let items = reactionPicker.currentReactionItems()
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            ReactionManager.setCustomReactionSet(items, tx: transaction)
        }
        self.reactionPickerConfigurationListener?.didCompleteReactionPickerConfiguration()
        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        dismiss(animated: true, completion: nil)
    }

}

extension CustomReactionPickerConfigViewController: MessageReactionPickerDelegate {
    func didSelectReaction(
        _ reaction: CustomReactionItem,
        isRemoving: Bool,
        inPosition position: Int
    ) {
        if presentedViewController != nil {
            self.reactionPicker.endReplaceAnimation()
            presentedViewController?.dismiss(animated: true, completion: nil)
            return
        }

        let picker = ReactionPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] newReaction in
            guard let self else { return }

            guard let newReaction else {
                self.reactionPicker.endReplaceAnimation()
                return
            }

            self.reactionPicker.replaceReaction(
                reaction,
                new: newReaction,
                inPosition: position,
            )
            self.reactionPicker.endReplaceAnimation()
        }

        reactionPicker.startReplaceAnimation(focusedReaction: reaction, inPosition: position)
        present(picker, animated: true)
    }

    func didSelectMore() {
        // No-op for configuration
    }
}
