//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

private extension ContactSupportViewController.Filter {
    var emailFilterString: String {
        return switch self {
        case .featureRequest: "Feature Request"
        case .question: "Question"
        case .feedback: "Feedback"
        case .somethingNotWorking: "Something Not Working"
        case .other: "Other"
        case .payments: "Payments"
        case .donationsAndBadges: "Donations & Badges"
        }
    }

    var localizedString: String {
        switch self {
        case .featureRequest:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_FEATURE_REQUEST",
                comment: "The localized representation of the 'feature request' support filter.",
            )
        case .question:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_QUESTION",
                comment: "The localized representation of the 'question' support filter.",
            )
        case .feedback:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_FEEDBACK",
                comment: "The localized representation of the 'feedback' support filter.",
            )
        case .somethingNotWorking:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_SOMETHING_NOT_WORKING",
                comment: "The localized representation of the 'something not working' support filter.",
            )
        case .other:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_OTHER",
                comment: "The localized representation of the 'other' support filter.",
            )
        case .payments:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_PAYMENTS",
                comment: "The localized representation of the 'payments' support filter.",
            )
        case .donationsAndBadges:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_DONATIONS_AND_BADGES",
                comment: "The localized representation of the 'Donations & Badges' support filter.",
            )
        }
    }

    var localizedShortString: String {
        switch self {
        case .featureRequest:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_FEATURE_REQUEST_SHORT",
                comment: "A brief localized representation of the 'feature request' support filter.",
            )
        case .question:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_QUESTION_SHORT",
                comment: "A brief localized representation of the 'question' support filter.",
            )
        case .feedback:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_FEEDBACK_SHORT",
                comment: "A brief localized representation of the 'feedback' support filter.",
            )
        case .somethingNotWorking:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_SOMETHING_NOT_WORKING_SHORT",
                comment: "A brief localized representation of the 'something not working' support filter.",
            )
        case .other:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_OTHER_SHORT",
                comment: "A brief localized representation of the 'other' support filter.",
            )
        case .payments:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_PAYMENTS_SHORT",
                comment: "A brief localized representation of the 'payments' support filter.",
            )
        case .donationsAndBadges:
            return OWSLocalizedString(
                "CONTACT_SUPPORT_FILTER_DONATIONS_AND_BADGES_SHORT",
                comment: "A brief localized representation of the 'Donations & Badges' support filter.",
            )
        }
    }
}

final class ContactSupportViewController: OWSTableViewController2 {
    enum Filter: CaseIterable {
        case featureRequest
        case question
        case feedback
        case somethingNotWorking
        case other
        case payments
        case donationsAndBadges
    }

    var selectedFilter: Filter?

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem?.tintColor = .Signal.accent

        shouldAvoidKeyboard = true

        tableView.keyboardDismissMode = .interactive
        tableView.separatorInsetReference = .fromCellEdges
        tableView.separatorInset = .zero

        rebuildTableContents()
        setupNavigationBar()
        setupDataProviderViews()
    }

    // MARK: - Data providers

    // Any views that provide model information are instantiated by the view controller directly
    // Views that are just chrome are put together in the `constructTableContents()` function

    private let descriptionField = TextViewWithPlaceholder()
    private let debugSwitch = UISwitch()
    private let emojiPicker = EmojiMoodPickerView()

    private func setupDataProviderViews() {
        descriptionField.delegate = self
        descriptionField.placeholderText = OWSLocalizedString(
            "SUPPORT_DESCRIPTION_PLACEHOLDER",
            comment: "Placeholder string for support description",
        )
        debugSwitch.isOn = true
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapCancel()
        }
        navigationItem.rightBarButtonItem = .button(
            title: CommonStrings.nextButton,
            style: .done,
            action: { [weak self] in
                self?.didTapNext()
            },
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private func updateRightBarButton() {
        navigationItem.rightBarButtonItem?.isEnabled = ((descriptionField.text?.count ?? 0) > 10) && selectedFilter != nil
    }

    private func rebuildTableContents() {
        contents = constructContents()
    }

    // MARK: - View transitions

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.descriptionField.scrollToFocus(in: self.tableView, animated: true)
        }, completion: nil)
    }

    private var showSpinnerOnNextButton = false {
        didSet {
            guard showSpinnerOnNextButton else {
                navigationItem.rightBarButtonItem?.customView = nil
                return
            }

            let indicatorStyle: UIActivityIndicatorView.Style
            indicatorStyle = .medium
            let spinner = UIActivityIndicatorView(style: indicatorStyle)
            spinner.startAnimating()

            let label = UILabel()
            label.text = OWSLocalizedString(
                "SUPPORT_LOG_UPLOAD_IN_PROGRESS",
                comment: "A string in the navigation bar indicating that the support request is uploading logs",
            )
            label.textColor = .Signal.secondaryLabel

            let stackView = UIStackView(arrangedSubviews: [label, spinner])
            stackView.spacing = 4
            navigationItem.rightBarButtonItem?.customView = stackView
        }
    }

    // MARK: - Actions

    private func didTapCancel() {
        self.currentEmailComposeTask?.cancel()
        navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private var currentEmailComposeTask: Task<Void, any Error>?

    private func didTapNext() {
        let logDumper = DebugLogDumper.fromGlobals()
        let emailRequest = SupportEmailModel(
            userDescription: descriptionField.text,
            emojiMood: emojiPicker.selectedMood,
            supportFilter: selectedFilter.map { "iOS \($0.emailFilterString)" },
            debugLogPolicy: debugSwitch.isOn ? .attemptUpload(logDumper) : nil,
            hasRecentChallenge: logDumper.challengeReceivedRecently(),
        )

        showSpinnerOnNextButton = true

        Task { @MainActor in
            do {
                let composeTask = Task {
                    try await ComposeSupportEmailOperation(model: emailRequest).perform()
                }
                self.currentEmailComposeTask = composeTask
                try await composeTask.value
                self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
            } catch {
                let alertTitle = error.userErrorDescription
                let alertMessage = OWSLocalizedString(
                    "SUPPORT_EMAIL_ERROR_ALERT_DESCRIPTION",
                    comment: "Message for alert dialog presented when a support email failed to send",
                )
                OWSActionSheets.showActionSheet(title: alertTitle, message: alertMessage)
            }

            self.currentEmailComposeTask = nil
            self.showSpinnerOnNextButton = false
        }
    }
}

// MARK: - <TextViewWithPlaceholderDelegate>

extension ContactSupportViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        updateRightBarButton()

        // Disable interactive presentation if the user has entered text
        isModalInPresentation = !textView.text.isEmptyOrNil

        _textViewDidUpdateText(textView)
    }
}

// MARK: - Table view content builders

extension ContactSupportViewController {

    private func constructContents() -> OWSTableContents {

        let titleText = OWSLocalizedString(
            "HELP_CONTACT_US",
            comment: "Help item allowing the user to file a support request",
        )
        let contactHeaderText = OWSLocalizedString(
            "SUPPORT_CONTACT_US_HEADER",
            comment: "Header of support description field",
        )
        let emojiHeaderText = OWSLocalizedString(
            "SUPPORT_EMOJI_PROMPT",
            comment: "Header for emoji mood selection",
        )
        let faqPromptText = OWSLocalizedString(
            "SUPPORT_FAQ_PROMPT",
            comment: "Label in support request informing user about Signal FAQ",
        )

        return OWSTableContents(title: titleText, sections: [

            OWSTableSection(title: contactHeaderText, items: [

                // Filter selection
                OWSTableItem(
                    customCellBlock: { [weak self] in
                        guard let self else { return UITableViewCell() }
                        return OWSTableItem.buildCell(
                            itemName: OWSLocalizedString(
                                "CONTACT_SUPPORT_FILTER_PROMPT",
                                comment: "Prompt telling the user to select a filter for their support request.",
                            ),
                            accessoryText: self.selectedFilter?.localizedShortString ?? OWSLocalizedString(
                                "CONTACT_SUPPORT_SELECT_A_FILTER",
                                comment: "Placeholder telling user they must select a filter.",
                            ),
                            accessoryTextColor: self.selectedFilter == nil ? .placeholderText : nil,
                        )
                    },
                    actionBlock: { [weak self] in
                        self?.showFilterPicker()
                    },
                ),

                // Description field
                self.textViewItem(self.descriptionField, minimumHeight: 125),

                // Debug log switch
                OWSTableItem(customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.createDebugLogCell()
                }),

                // FAQ prompt
                OWSTableItem(
                    customCellBlock: {
                        let cell = OWSTableItem.newCell()
                        cell.textLabel?.font = UIFont.dynamicTypeBody
                        cell.textLabel?.adjustsFontForContentSizeCategory = true
                        cell.textLabel?.numberOfLines = 0
                        cell.textLabel?.text = faqPromptText
                        cell.textLabel?.textColor = .Signal.accent
                        return cell
                    },
                    actionBlock: { [weak self] in
                        let vc = SFSafariViewController(url: URL.Support.generic)
                        self?.present(vc, animated: true)
                    },
                ),
            ]),

            // The emoji picker is placed in the section footer to avoid tableview separators
            // As far as I can tell, there's no way for a grouped UITableView to not add separators
            // between the header and the first row without messing in the UITableViewCell's hierarchy
            //
            // UITableViewCell.separatorInset looks like it would work, but it only applies to separators
            // between cells, not between the header and the footer

            OWSTableSection(title: emojiHeaderText, footerView: createEmojiFooterView()),
        ])
    }

    private func createDebugLogCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let label = UILabel()
        label.text = OWSLocalizedString(
            "SUPPORT_INCLUDE_DEBUG_LOG",
            comment: "Label describing support switch to attach debug logs",
        )
        label.font = UIFont.dynamicTypeBody
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .label

        let infoButton = OWSButton(imageName: "help", tintColor: .Signal.secondaryLabel) { [weak self] in
            let vc = SFSafariViewController(url: URL.Support.debugLogs)
            self?.present(vc, animated: true)
        }
        infoButton.accessibilityLabel = OWSLocalizedString(
            "DEBUG_LOG_INFO_BUTTON",
            comment: "Accessibility label for the ? vector asset used to get info about debug logs",
        )

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(infoButton)
        cell.accessoryView = debugSwitch

        label.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        label.setCompressionResistanceHigh()

        infoButton.autoPinHeightToSuperviewMargins()
        infoButton.autoPinLeading(toTrailingEdgeOf: label, offset: 6)
        infoButton.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        return cell
    }

    private func createEmojiFooterView() -> UIView {
        let containerView = UIView()

        // These constants were pulled from OWSTableViewController to get things to line up right
        let horizontalEdgeInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
        containerView.directionalLayoutMargins.leading = horizontalEdgeInset
        containerView.directionalLayoutMargins.trailing = horizontalEdgeInset

        containerView.addSubview(emojiPicker)
        emojiPicker.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        return containerView
    }

    private func showFilterPicker() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString(
            "CONTACT_SUPPORT_FILTER_PROMPT",
            comment: "Prompt telling the user to select a filter for their support request.",
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        for filter in Filter.allCases {
            let action = ActionSheetAction(title: filter.localizedString) { [weak self] _ in
                self?.selectedFilter = filter
                self?.updateRightBarButton()
                self?.rebuildTableContents()
            }
            actionSheet.addAction(action)
        }

        presentActionSheet(actionSheet)
    }
}
