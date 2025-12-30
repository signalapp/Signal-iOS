//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class MemberRequestView: ConversationBottomPanelView {

    private let thread: TSThread

    private weak var fromViewController: UIViewController?

    weak var delegate: MessageRequestDelegate?

    init(threadViewModel: ThreadViewModel, fromViewController: UIViewController) {
        self.thread = threadViewModel.threadRecord
        owsAssertDebug(thread is TSGroupThread)
        self.fromViewController = fromViewController

        super.init(frame: .zero)

        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = OWSLocalizedString(
            "MESSAGE_REQUESTS_CONVERSATION_REQUEST_INDICATOR",
            comment: "Indicator that you have requested to join this group.",
        )
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping

        let cancelButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "MESSAGE_REQUESTS_CANCEL_REQUEST_BUTTON",
                comment: "Label for button to cancel your request to join the group.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancelButton()
            },
        )
        cancelButton.configuration?.baseForegroundColor = .Signal.red
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButtonContainer = UIView.container()
        cancelButtonContainer.addSubview(cancelButton)
        cancelButtonContainer.addConstraints([
            cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: cancelButtonContainer.leadingAnchor, constant: 18),
            cancelButton.centerXAnchor.constraint(equalTo: cancelButtonContainer.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: cancelButtonContainer.bottomAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [label, cancelButtonContainer])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        addConstraints([
            stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    private func didTapCancelButton() {
        showCancelRequestUI()
    }

    private func showCancelRequestUI() {
        guard let fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        let title = OWSLocalizedString(
            "MESSAGE_REQUESTS_CANCEL_REQUEST_CONFIRM_TITLE",
            comment: "Title for the confirmation alert when cancelling your request to join the group.",
        )
        let actionSheet = ActionSheetController(title: title)

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.yesButton,
            style: .destructive,
        ) { [weak self] _ in
            self?.cancelRequestToJoin()
        })
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.noButton,
            style: .cancel,
        ) { _ in
            // Do nothing.
        })

        fromViewController.presentActionSheet(actionSheet)
    }

    private func cancelRequestToJoin() {
        guard
            let fromViewController,
            let groupThread = thread as? TSGroupThread,
            let groupModelV2 = groupThread.groupModel as? TSGroupModelV2
        else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Missing properties needed to update group"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: fromViewController,
            updateBlock: {
                try await GroupManager.cancelRequestToJoin(groupModel: groupModelV2)
            },
            completion: nil,
        )
    }
}
