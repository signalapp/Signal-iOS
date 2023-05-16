//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import SignalUI

class MemberRequestView: UIStackView {

    private let thread: TSThread

    private weak var fromViewController: UIViewController?

    weak var delegate: MessageRequestDelegate?

    init(threadViewModel: ThreadViewModel, fromViewController: UIViewController) {
        let thread = threadViewModel.threadRecord
        self.thread = thread
        owsAssertDebug(thread as? TSGroupThread != nil)
        self.fromViewController = fromViewController

        super.init(frame: .zero)

        createContents()
    }

    private func createContents() {
        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaInset = safeAreaInsets.bottom

        autoresizingMask = .flexibleHeight

        axis = .vertical
        spacing = 11
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 20 + safeAreaInset, trailing: 16)
        isLayoutMarginsRelativeArrangement = true
        alignment = .fill

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = OWSLocalizedString("MESSAGE_REQUESTS_CONVERSATION_REQUEST_INDICATOR",
                                       comment: "Indicator that you have requested to join this group.")
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addArrangedSubview(label)

        let cancelTitle = OWSLocalizedString("MESSAGE_REQUESTS_CANCEL_REQUEST_BUTTON",
                                            comment: "Label for button to cancel your request to join the group.")
        let cancelButton = OWSFlatButton.button(title: cancelTitle,
                                                 font: UIFont.dynamicTypeBody.semibold(),
                                                 titleColor: Theme.secondaryTextAndIconColor,
                                                 backgroundColor: Theme.washColor,
                                                 target: self,
                                                 selector: #selector(didTapCancelButton))
        cancelButton.autoSetHeightUsingFont()
        addArrangedSubview(cancelButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    // MARK: -

    @objc
    private func didTapCancelButton(_ sender: UIButton) {
        showCancelRequestUI()
    }

    func showCancelRequestUI() {
        guard let fromViewController = fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        let title = OWSLocalizedString("MESSAGE_REQUESTS_CANCEL_REQUEST_CONFIRM_TITLE",
                                            comment: "Title for the confirmation alert when cancelling your request to join the group.")
        let actionSheet = ActionSheetController(title: title)

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.yesButton,
                                                style: .destructive) { [weak self] _ in
                                                    self?.cancelMemberRequest()
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.noButton,
                                                style: .destructive) { _ in
                                                    // Do nothing.
        })

        fromViewController.presentActionSheet(actionSheet)
    }

    func cancelMemberRequest() {
        guard let fromViewController = fromViewController,
              let groupThread = thread as? TSGroupThread,
              let groupModelV2 = groupThread.groupModel as? TSGroupModelV2
        else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Missing properties needed to update group"))
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: fromViewController,
            withGroupModel: groupModelV2,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.cancelMemberRequestsV2(groupModel: groupModelV2)
            },
            completion: nil
        )
    }
}
