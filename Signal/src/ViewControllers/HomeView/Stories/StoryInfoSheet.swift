//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import SignalUI

final class StoryInfoSheet: OWSTableSheetViewController {
    private(set) var storyMessage: StoryMessage
    let context: StoryContext
    var dismissHandler: (() -> Void)?

    private let spoilerState: SpoilerRenderState

    override var sheetBackgroundColor: UIColor { .ows_gray90 }

    init(storyMessage: StoryMessage, context: StoryContext, spoilerState: SpoilerRenderState) {
        self.storyMessage = storyMessage
        self.context = context
        self.spoilerState = spoilerState
        super.init()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        tableViewController.forceDarkMode = true
        tableViewController.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
    }

    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        storyMessage = SSKEnvironment.shared.databaseStorageRef.read { StoryMessage.anyFetch(uniqueId: storyMessage.uniqueId, transaction: $0) ?? storyMessage }

        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let metadataSection = OWSTableSection()
        metadataSection.hasBackground = false
        contents.add(metadataSection)

        metadataSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            guard let stackView = self?.buildMetadataStackView() else { return cell }
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        switch storyMessage.manifest {
        case .outgoing(let recipientStates):
            contents.add(sections: buildStatusSections(for: recipientStates))
        case .incoming:
            contents.add(buildSenderSection())
        }
    }

    private let byteCountFormatter: ByteCountFormatter = ByteCountFormatter()
    private func buildMetadataStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical

        let timestampLabel = buildValueLabel(
            name: OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                comment: "Label for the 'sent date & time' field of the 'message metadata' view."
            ),
            value: DateUtil.formatPastTimestampRelativeToNow(storyMessage.timestamp)
        )
        stackView.addArrangedSubview(timestampLabel)
        timestampLabel.isUserInteractionEnabled = true
        timestampLabel.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressTimestamp)))

        switch storyMessage.manifest {
        case .outgoing: break
        case .incoming(let receivedState):
            guard let receivedTimestamp = receivedState.receivedTimestamp else {
                owsFailDebug("Unexpectedly missing received timestamp for story message")
                break
            }

            let receivedTimestampLabel = buildValueLabel(
                name: OWSLocalizedString(
                    "MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                    comment: "Label for the 'received date & time' field of the 'message metadata' view."
                ),
                value: DateUtil.formatPastTimestampRelativeToNow(receivedTimestamp)
            )
            stackView.addArrangedSubview(receivedTimestampLabel)
        }

        switch storyMessage.attachment {
        case .text: break
        case .media:
            guard let attachment = SSKEnvironment.shared.databaseStorageRef.read(block: { storyMessage.fileAttachment(tx: $0) })?.attachment else {
                owsFailDebug("Missing attachment for story message")
                break
            }

            if let formattedByteCount = byteCountFormatter.string(for: attachment.asStream()?.unencryptedByteCount) {
                stackView.addArrangedSubview(buildValueLabel(
                    name: OWSLocalizedString(
                        "MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                        comment: "Label for file size of attachments in the 'message metadata' view."
                    ),
                    value: formattedByteCount
                ))
            } else {
                owsFailDebug("formattedByteCount was unexpectedly nil")
            }
        }

        return stackView
    }

    private func buildSenderSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "MESSAGE_DETAILS_VIEW_SENT_FROM_TITLE",
            comment: "Title for the 'sent from' section on the 'message details' view."
        )
        section.hasBackground = false
        section.add(contactItem(
            for: storyMessage.authorAddress,
            accessoryText: DateUtil.formatPastTimestampRelativeToNow(storyMessage.timestamp)
        ))
        return section
    }

    private func buildStatusSections(for recipientStates: [ServiceId: StoryRecipientState]) -> [OWSTableSection] {
        let recipientStates = recipientStates.filter { $1.isValidForContext(context) }

        var sections = [OWSTableSection]()

        let orderedSendingStates: [OWSOutgoingMessageRecipientStatus] = [
            .sent,
            .sending,
            .pending,
            .failed,
            .skipped
        ]

        let groupedRecipientStates = Dictionary(grouping: recipientStates) { $0.value.sendingState }

        for state in orderedSendingStates {
            guard let recipients = groupedRecipientStates[state], !recipients.isEmpty else { continue }

            let sortedRecipientAddresses = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerImplRef.sortSignalServiceAddresses(
                    recipients.map { SignalServiceAddress($0.key) },
                    transaction: tx
                )
            }

            let section = OWSTableSection()
            section.hasBackground = false
            section.headerTitle = sectionTitle(for: state)
            sections.append(section)

            for address in sortedRecipientAddresses {
                section.add(contactItem(
                    for: address,
                    accessoryText: statusMessage(for: state)
                ))
            }
        }

        return sections
    }

    private func sectionTitle(for state: OWSOutgoingMessageRecipientStatus) -> String {
        switch state {
        case .sent, .delivered, .read, .viewed:
            return OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENT",
                comment: "Status label for messages which are sent."
            )
        case .sending:
            return OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENDING",
                comment: "Status label for messages which are sending."
            )
        case .pending:
            return OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_MESSAGE_STATUS_PAUSED",
                comment: "Status label for messages which are paused."
            )
        case .failed:
            return OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_MESSAGE_STATUS_FAILED",
                comment: "Status label for messages which are failed."
            )
        case .skipped:
            return OWSLocalizedString(
                "MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SKIPPED",
                comment: "Status label for messages which were skipped."
            )
        }
    }

    private func statusMessage(for state: OWSOutgoingMessageRecipientStatus) -> String {
        switch state {
        case .sent, .delivered, .read, .viewed:
            return DateUtil.formatPastTimestampRelativeToNow(storyMessage.timestamp)
        case .sending:
            return OWSLocalizedString("MESSAGE_STATUS_SENDING", comment: "message status while message is sending.")
        case .pending:
            return OWSLocalizedString("MESSAGE_STATUS_PENDING_SHORT", comment: "Label indicating that a message send was paused.")
        case .failed:
            return OWSLocalizedString("MESSAGE_STATUS_FAILED_SHORT", comment: "status message for failed messages")
        case .skipped:
            return OWSLocalizedString(
                "MESSAGE_STATUS_RECIPIENT_SKIPPED",
                comment: "message status if message delivery to a recipient is skipped. We skip delivering group messages to users who have left the group or unregistered their Signal account."
            )
        }
    }

    @objc
    private func didLongPressTimestamp(sender: UIGestureRecognizer) {
        guard sender.state == .began else { return }

        let messageTimestamp = "\(storyMessage.timestamp)"
        UIPasteboard.general.string = messageTimestamp

        let toast = ToastController(text: OWSLocalizedString(
            "MESSAGE_DETAIL_VIEW_DID_COPY_SENT_TIMESTAMP",
            comment: "Toast indicating that the user has copied the sent timestamp."
        ))
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }

    private func valueLabelAttributedText(name: String, value: String) -> NSAttributedString {
        .composed(of: [
            name.styled(with: .font(UIFont.dynamicTypeFootnoteClamped.semibold())),
            " ",
            value
        ])
    }

    private func buildValueLabel(name: String, value: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.darkThemePrimaryColor
        label.font = .dynamicTypeFootnoteClamped
        label.attributedText = valueLabelAttributedText(name: name, value: value)
        return label
    }

    private func contactItem(for address: SignalServiceAddress, accessoryText: String) -> OWSTableItem {
        return .init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let tableView = self.tableViewController.tableView
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ContactTableViewCell.reuseIdentifier
            ) as? ContactTableViewCell else {
                owsFailDebug("Missing cell.")
                return UITableViewCell()
            }

            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asUser)
                configuration.forceDarkAppearance = true
                configuration.accessoryView = self.buildAccessoryView(
                    text: accessoryText,
                    transaction: transaction
                )
                cell.configure(configuration: configuration, transaction: transaction)
            }
            return cell
        }, actionBlock: { [weak self] in
            guard let self = self else { return }
            ProfileSheetSheetCoordinator(
                address: address,
                groupViewHelper: nil,
                spoilerState: self.spoilerState
            )
            .presentAppropriateSheet(from: self)
        })
    }

    private func buildAccessoryView(
        text: String,
        transaction: DBReadTransaction
    ) -> ContactCellAccessoryView {
        let label = CVLabel()
        let labelConfig = CVLabelConfig.unstyledText(
            text,
            font: .dynamicTypeFootnoteClamped,
            textColor: Theme.darkThemeSecondaryTextAndIconColor
        )
        labelConfig.applyForRendering(label: label)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: .greatestFiniteMagnitude)

        return ContactCellAccessoryView(accessoryView: label, size: labelSize)
    }
}

extension StoryInfoSheet: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.storyMessageRowIds.contains(storyMessage.id!) else { return }
        updateTableContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateTableContents()
    }

    func databaseChangesDidReset() {
        updateTableContents()
    }
}
