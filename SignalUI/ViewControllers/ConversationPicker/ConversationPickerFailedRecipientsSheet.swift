//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class ConversationPickerFailedRecipientsSheet: OWSTableSheetViewController {

    let failedAttachments: [SignalAttachment]
    let failedStoryConversationItems: [StoryConversationItem]
    let remainingConversationItems: [ConversationItem]
    let onApprove: () -> Void

    public init(
        failedAttachments: [SignalAttachment],
        failedStoryConversationItems: [StoryConversationItem],
        remainingConversationItems: [ConversationItem],
        onApprove: @escaping () -> Void
    ) {
        assert(failedAttachments.isEmpty.negated)
        assert(failedStoryConversationItems.isEmpty.negated)
        self.failedAttachments = failedAttachments
        self.failedStoryConversationItems = failedStoryConversationItems
        self.remainingConversationItems = remainingConversationItems
        self.onApprove = onApprove
        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableViewController.tableView.register(
            ConversationPickerCell.self,
            forCellReuseIdentifier: ConversationPickerCell.reuseIdentifier
        )

        let doneButton = OWSButton(title: CommonStrings.okayButton) { [weak self] in
            self?.dismiss(animated: true) {
                self?.onApprove()
            }
        }
        doneButton.dimsWhenHighlighted = true
        doneButton.layer.cornerRadius = 8
        doneButton.backgroundColor = .ows_accentBlue
        doneButton.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        footerStack.addArrangedSubview(doneButton)
        doneButton.autoSetDimension(.height, toSize: 48)
        doneButton.autoPinWidthToSuperview(withMargin: 48)
        doneButton.autoHCenterInSuperview()

        footerStack.addArrangedSubview(SpacerView(preferredHeight: 20))
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = generateTableContents()
        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    private func generateTableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.separatorInsetLeading = NSNumber(value: OWSTableViewController2.cellHInnerMargin + 32)

        let headerTitle: String
        if remainingConversationItems.isEmpty {
            headerTitle = OWSLocalizedString(
                "STORIES_SHARESHEET_UNABLE_TO_SEND_SEND_TITLE",
                comment: "Title shown when failing to send an incompatible file to stories via the sharesheet."
            )
        } else {
            headerTitle = OWSLocalizedString(
                "STORIES_SHARESHEET_PARTIAL_SEND_TITLE",
                comment: "Title shown when failing to send an incompatible file to stories, but still sending to non-story conversations."
            )
        }

        let subtitleFormat = OWSLocalizedString(
            "STORIES_SHARESHEET_PARTIAL_SEND_SUBTITLE_%d",
            tableName: "PluralAware",
            comment: "Subtitle shown when failing to send a single incompatible file to stories via the sharesheet."
        )
        let headerSubtitle = String.localizedStringWithFormat(
            subtitleFormat,
            failedStoryConversationItems.count
        )

        let headerView = SheetHeaderView(
            title: headerTitle,
            subtitle: headerSubtitle
        )
        headerSection.customHeaderView = headerView
        contents.addSection(headerSection)

        let failedStoriesSection = OWSTableSection()
        failedStoriesSection.headerTitle = OWSLocalizedString(
            "STORIES_SHARESHEET_PARTIAL_SEND_STORIES_SECTION_TITLE",
            comment: "Section title shown when failing to send an incompatible file to stories, but still sending to non-story conversations."
        )
        for item in failedStoryConversationItems {
            failedStoriesSection.add(OWSTableItem(dequeueCellBlock: { tableView in
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ConversationPickerCell.reuseIdentifier) as? ConversationPickerCell else {
                    return UITableViewCell()
                }
                Self.databaseStorage.read {
                    cell.configure(conversationItem: item, transaction: $0)
                }
                cell.showsSelectionUI = false
                return cell
            }))
        }
        contents.addSection(failedStoriesSection)

        if !remainingConversationItems.isEmpty {
            let remainingConversationsSection = OWSTableSection()
            remainingConversationsSection.headerTitle = OWSLocalizedString(
                "STORIES_SHARESHEET_PARTIAL_SEND_REMAINING_SECTION_TITLE",
                comment: "Section title shown when sending to non-story conversations but failing to send the file to stories."
            )
            for item in remainingConversationItems {
                remainingConversationsSection.add(OWSTableItem(dequeueCellBlock: { tableView in
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ConversationPickerCell.reuseIdentifier) as? ConversationPickerCell else {
                        return UITableViewCell()
                    }
                    Self.databaseStorage.read {
                        cell.configure(conversationItem: item, transaction: $0)
                    }
                    cell.showsSelectionUI = false
                    return cell
                }))
            }
            contents.addSection(remainingConversationsSection)
        }

        return contents
    }

    private class SheetHeaderView: UIView {

        let titleLabel = UILabel()
        let subtitleLabel = UILabel()

        init(title: String, subtitle: String) {
            super.init(frame: .zero)

            titleLabel.text = title
            titleLabel.textAlignment = .center
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            addSubview(titleLabel)

            subtitleLabel.numberOfLines = 0
            subtitleLabel.text = subtitle
            subtitleLabel.textAlignment = .center
            subtitleLabel.font = .ows_dynamicTypeSubheadline
            subtitleLabel.textColor = Theme.primaryTextColor
            addSubview(subtitleLabel)

            titleLabel.autoPinWidthToSuperview(withMargin: 24)
            titleLabel.autoPinTopToSuperviewMargin()

            subtitleLabel.autoHCenterInSuperview()
            subtitleLabel.autoPinWidthToSuperview(withMargin: 24)
            subtitleLabel.autoPinBottomToSuperviewMargin()
            subtitleLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 8)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }
    }
}
