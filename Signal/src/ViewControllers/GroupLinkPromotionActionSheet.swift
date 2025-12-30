//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class GroupLinkPromotionActionSheet: UIView {

    private weak var conversationViewController: ConversationViewController?

    private let groupThread: TSGroupThread

    weak var actionSheetController: ActionSheetController?

    init(groupThread: TSGroupThread, conversationViewController: ConversationViewController) {
        self.groupThread = groupThread
        self.conversationViewController = conversationViewController

        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "GROUP_LINK_PROMOTION_ALERT_TITLE",
            comment: "Title for the 'group link promotion' alert view.",
        )
        titleLabel.textColor = .Signal.label
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textAlignment = .natural

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "GROUP_LINK_PROMOTION_ALERT_SUBTITLE",
            comment: "Subtitle for the 'group link promotion' alert view.",
        )
        subtitleLabel.textColor = .Signal.label
        subtitleLabel.font = .dynamicTypeBody
        subtitleLabel.textAlignment = .natural
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        topStack.axis = .vertical
        topStack.spacing = 4
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.directionalLayoutMargins = .init(top: 14, leading: 14, bottom: 20, trailing: 14)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStack)
        addConstraints([
            topStack.topAnchor.constraint(equalTo: topAnchor),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let buttonStackTopAnchor: NSLayoutYAxisAnchor
        if isGroupLinkEnabled {
            buttonStackTopAnchor = topStack.bottomAnchor
        } else {
            let switchLabel = UILabel()
            switchLabel.text = OWSLocalizedString(
                "GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_SWITCH",
                comment: "Label for the 'approve new group members' switch.",
            )
            switchLabel.setCompressionResistanceHorizontalHigh()

            memberApprovalSwitch.setCompressionResistanceHorizontalHigh()

            let memberApprovalStack = UIStackView(arrangedSubviews: [
                switchLabel,
                .hStretchingSpacer(),
                memberApprovalSwitch,
            ])
            memberApprovalStack.axis = .horizontal
            memberApprovalStack.alignment = .center
            memberApprovalStack.distribution = .fill
            memberApprovalStack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 10)
            memberApprovalStack.isLayoutMarginsRelativeArrangement = true
            memberApprovalStack.addBackgroundView(
                withBackgroundColor: .Signal.secondaryGroupedBackground,
                cornerRadius: OWSTableViewController2.cellRounding,
            )

            let captionLabel = UILabel()
            captionLabel.text = OWSLocalizedString(
                "GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_EXPLANATION",
                comment: "Explanation of the 'approve new group members' switch.",
            )
            captionLabel.textColor = .Signal.secondaryLabel
            captionLabel.font = .dynamicTypeFootnote
            captionLabel.numberOfLines = 0
            captionLabel.lineBreakMode = .byWordWrapping
            captionLabel.translatesAutoresizingMaskIntoConstraints = false

            let captionContainer = UIView()
            captionContainer.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
            captionContainer.addSubview(captionLabel)
            captionContainer.addConstraints([
                captionLabel.topAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.topAnchor),
                captionLabel.leadingAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.leadingAnchor),
                captionLabel.trailingAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.trailingAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.bottomAnchor),
            ])

            let middleStack = UIStackView(arrangedSubviews: [memberApprovalStack, captionContainer])
            middleStack.axis = .vertical
            middleStack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(middleStack)
            addConstraints([
                middleStack.topAnchor.constraint(equalTo: topStack.bottomAnchor),
                middleStack.leadingAnchor.constraint(equalTo: leadingAnchor),
                middleStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])

            buttonStackTopAnchor = middleStack.bottomAnchor
        }

        // Two buttons at the bottom
        let topButton: UIButton
        if isGroupLinkEnabled {
            topButton = UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "GROUP_LINK_PROMOTION_ALERT_SHARE_LINK",
                    comment: "Label for the 'share link' button in the 'group link promotion' alert view.",
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.dismissAndShareLink()
                },
            )
        } else {
            topButton = UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "GROUP_LINK_PROMOTION_ALERT_ENABLE_AND_SHARE_LINK",
                    comment: "Label for the 'enable and share link' button in the 'group link promotion' alert view.",
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.enableAndShareLink()
                },
            )
        }
        let cancelButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.dismissAlert()
            },
        )

        let buttonStack = UIStackView.verticalButtonStack(buttons: [topButton, cancelButton], isFullWidthButtons: true)
        buttonStack.directionalLayoutMargins = .zero
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)
        addConstraints([
            buttonStack.topAnchor.constraint(equalTo: buttonStackTopAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    private var isGroupLinkEnabled: Bool {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return false
        }
        switch groupModel.groupInviteLinkMode {
        case .disabled:
            return false
        case .enabledWithApproval, .enabledWithoutApproval:
            return true
        }
    }

    private let memberApprovalSwitch = UISwitch()

    // MARK: - Events

    private func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }

    private func enableAndShareLink() {
        guard let actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        let approveNewMembers = memberApprovalSwitch.isOn
        let linkMode = GroupLinkViewUtils.linkMode(
            isGroupInviteLinkEnabled: true,
            approveNewMembers: approveNewMembers,
        )
        GroupLinkViewUtils.updateLinkMode(
            groupModelV2: groupModelV2,
            linkMode: linkMode,
            fromViewController: actionSheetController,
            completion: { [weak self] in
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let groupThread = databaseStorage.read { tx in
                    return TSGroupThread.fetch(groupId: groupModelV2.groupId, transaction: tx)
                }
                guard let groupModelV2 = groupThread?.groupModel as? TSGroupModelV2 else {
                    owsFailDebug("Invalid groupModel.")
                    return
                }
                self?.dismissActionSheetAndShareLink(groupModelV2: groupModelV2)
            },
        )
    }

    private func dismissAndShareLink() {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        dismissActionSheetAndShareLink(groupModelV2: groupModelV2)
    }

    private func dismissActionSheetAndShareLink(groupModelV2: TSGroupModelV2) {
        guard let actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        actionSheetController.dismiss(animated: true) {
            self.showShareLinkActionSheet(groupModelV2: groupModelV2)
        }
    }

    private func showShareLinkActionSheet(groupModelV2: TSGroupModelV2) {
        guard let conversationViewController else {
            owsFailDebug("Missing conversationViewController.")
            return
        }
        let sendMessageController = SendMessageController(fromViewController: conversationViewController)
        conversationViewController.sendMessageController = sendMessageController
        GroupLinkViewUtils.showShareLinkAlert(
            groupModelV2: groupModelV2,
            fromViewController: conversationViewController,
            sendMessageController: sendMessageController,
        )
    }
}
