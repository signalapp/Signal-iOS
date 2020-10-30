//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
class MemberRequestView: UIStackView {

    private let thread: TSThread

    private weak var fromViewController: UIViewController?

    @objc
    weak var delegate: MessageRequestDelegate?

    @objc
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
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = NSLocalizedString("MESSAGE_REQUESTS_CONVERSATION_REQUEST_INDICATOR",
                                       comment: "Indicator that you have requested to join this group.")
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addArrangedSubview(label)

        let cancelTitle = NSLocalizedString("MESSAGE_REQUESTS_CANCEL_REQUEST_BUTTON",
                                            comment: "Label for button to cancel your request to join the group.")
        let cancelButton = OWSFlatButton.button(title: cancelTitle,
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold,
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
    func didTapCancelButton(_ sender: UIButton) {
        showCancelRequestUI()
    }

    func showCancelRequestUI() {
        guard let fromViewController = fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        let title = NSLocalizedString("MESSAGE_REQUESTS_CANCEL_REQUEST_CONFIRM_TITLE",
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
        guard let fromViewController = fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: fromViewController,
                                                        updatePromiseBlock: {
                                                            self.cancelMemberRequestPromise()
        },
                                                        completion: { _ in
                                                            // Do nothing.
        })
    }

    func cancelMemberRequestPromise() -> Promise<Void> {
        guard let groupThread = thread as? TSGroupThread else {
            return Promise(error: OWSAssertionError("Invalid thread."))
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModelV2,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.cancelMemberRequestsV2(groupModel: groupModelV2)
        }.asVoid()
    }
}
