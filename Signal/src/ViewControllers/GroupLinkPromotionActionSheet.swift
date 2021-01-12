//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PromiseKit

@objc
public class GroupLinkPromotionActionSheet: UIView {

    private weak var conversationViewController: ConversationViewController?

    private let groupThread: TSGroupThread

    weak var actionSheetController: ActionSheetController?

    private let stackView = UIStackView()

    required init(groupThread: TSGroupThread,
                  conversationViewController: ConversationViewController) {
        self.groupThread = groupThread
        self.conversationViewController = conversationViewController

        super.init(frame: .zero)

        configure()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func present(fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    @objc
    public func configure() {
        let subviews = buildContents()

        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 48, leading: 20, bottom: 38, trailing: 24)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        layoutMargins = .zero
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        stackView.setContentHuggingHorizontalLow()
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

    private func buildContents() -> [UIView] {
        let builder = ActionSheetContentBuilder()

        builder.add(builder.buildTitleLabel(text: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_TITLE",
                                                                    comment: "Title for the 'group link promotion' alert view.")))

        builder.addVerticalSpacer(height: 8)

        builder.add(builder.buildLabel(text: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_SUBTITLE",
                                                               comment: "Subtitle for the 'group link promotion' alert view."),
                                       textAlignment: .center))

        let isGroupLinkEnabled = self.isGroupLinkEnabled

        if isGroupLinkEnabled {
            builder.addVerticalSpacer(height: 47)

            builder.addBottomButton(title: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_SHARE_LINK",
                                                             comment: "Label for the 'share link' button in the 'group link promotion' alert view."),
                                    titleColor: .white,
                                    backgroundColor: .ows_accentBlue,
                                    target: self,
                                    selector: #selector(dismissAndShareLink))
        } else {
            builder.addVerticalSpacer(height: 30)

            let memberApprovalStack = UIStackView()
            memberApprovalStack.axis = .horizontal
            memberApprovalStack.alignment = .center
            memberApprovalStack.distribution = .fill
            memberApprovalStack.layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 14)
            memberApprovalStack.isLayoutMarginsRelativeArrangement = true

            let borderView = UIView()
            borderView.layer.cornerRadius = 8
            borderView.layer.borderWidth = 1
            borderView.layer.borderColor = Theme.hairlineColor.cgColor
            memberApprovalStack.addSubview(borderView)
            borderView.autoPinEdgesToSuperviewEdges()

            let switchLabel = builder.buildLabel(text: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_SWITCH",
                                                                         comment: "Label for the 'approve new group members' switch."),
                                                 font: .ows_dynamicTypeBody2)
            memberApprovalStack.addArrangedSubview(switchLabel)
            switchLabel.setCompressionResistanceHorizontalHigh()

            memberApprovalStack.addArrangedSubview(UIView.hStretchingSpacer())

            memberApprovalStack.addArrangedSubview(memberApprovalSwitch)
            memberApprovalSwitch.setCompressionResistanceHorizontalHigh()

            builder.add(memberApprovalStack)

            builder.addVerticalSpacer(height: 8)

            builder.add(builder.buildLabel(text: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_EXPLANATION",
                                                                   comment: "Explanation of the 'approve new group members' switch."),
                                           textColor: Theme.secondaryTextAndIconColor,
                                           font: .ows_dynamicTypeBody2))

            builder.addVerticalSpacer(height: 47)

            builder.addBottomButton(title: NSLocalizedString("GROUP_LINK_PROMOTION_ALERT_ENABLE_AND_SHARE_LINK",
                                                             comment: "Label for the 'enable and share link' button in the 'group link promotion' alert view."),
                                    titleColor: .white,
                                    backgroundColor: .ows_accentBlue,
                                    target: self,
                                    selector: #selector(enableAndShareLink))
        }

        builder.addVerticalSpacer(height: 5)
        builder.addBottomButton(title: CommonStrings.cancelButton,
                                titleColor: .ows_accentBlue,
                                backgroundColor: .white,
                                target: self,
                                selector: #selector(dismissAlert))

        return builder.subviews
    }

    // MARK: - Events

    @objc
    func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }
}

// MARK: -

private extension GroupLinkPromotionActionSheet {

    @objc
    func enableAndShareLink() {
        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        let approveNewMembers = memberApprovalSwitch.isOn
        let linkMode = GroupLinkViewUtils.linkMode(isGroupInviteLinkEnabled: true,
                                                   approveNewMembers: approveNewMembers)
        GroupLinkViewUtils.updateLinkMode(groupModelV2: groupModelV2,
                                          linkMode: linkMode,
                                          description: self.logTag,
                                          fromViewController: actionSheetController) { [weak self] (groupThread) in
            guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid groupModel.")
                return
            }
            self?.dismissActionSheetAndShareLink(groupModelV2: groupModelV2)
        }
    }

    @objc
    func dismissAndShareLink() {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        dismissActionSheetAndShareLink(groupModelV2: groupModelV2)
    }

    private func dismissActionSheetAndShareLink(groupModelV2: TSGroupModelV2) {
        guard let actionSheetController = actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        actionSheetController.dismiss(animated: true) {
            self.showShareLinkActionSheet(groupModelV2: groupModelV2)
        }
    }

    private func showShareLinkActionSheet(groupModelV2: TSGroupModelV2) {
        guard let conversationViewController = conversationViewController else {
            owsFailDebug("Missing conversationViewController.")
            return
        }
        let sendMessageController = SendMessageController(fromViewController: conversationViewController)
        conversationViewController.sendMessageController = sendMessageController
        GroupLinkViewUtils.showShareLinkAlert(groupModelV2: groupModelV2,
                                              fromViewController: conversationViewController,
                                              sendMessageController: sendMessageController)
    }
}
