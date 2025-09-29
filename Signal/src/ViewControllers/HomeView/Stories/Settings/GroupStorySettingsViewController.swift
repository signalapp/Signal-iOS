//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class GroupStorySettingsViewController: OWSTableViewController2 {
    let thread: TSGroupThread
    let contextButton = ContextMenuButton(empty: ())

    init(thread: TSGroupThread) {
        self.thread = thread
        super.init()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()

        contextButton.tintColor = Theme.primaryIconColor
    }

    private func updateBarButtons() {
        title = thread.groupNameOrDefault

        contextButton.setImage(Theme.iconImage(.buttonMore), for: .normal)
        contextButton.setActions(actions: [
            UIAction(
                title: OWSLocalizedString(
                    "STORIES_GO_TO_CHAT_ACTION",
                    comment: "Context menu action to open the chat associated with the selected story"
                ),
                image: Theme.iconImage(.contextMenuOpenInChat),
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    self.dismiss(animated: true) {
                        SignalApp.shared.presentConversationForThread(
                            threadUniqueId: self.thread.uniqueId,
                            action: .compose,
                            animated: true
                        )
                    }
                }
            )
        ])

        navigationItem.rightBarButtonItem = .init(customView: contextButton)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateTableContents()
    }

    private var isShowingAllViewers = false
    private func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { self.setContents(contents, shouldReload: shouldReload) }

        let viewersSection = OWSTableSection()
        viewersSection.headerTitle = OWSLocalizedString(
            "GROUP_STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
            comment: "Section header for the 'viewers' section on the 'group story settings' view"
        )
        let format = OWSLocalizedString(
            "GROUP_STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER_FORMAT",
            comment: "Section footer for the 'viewers' section on the 'group story settings' view. Embeds {{ group name }}"
        )
        viewersSection.footerTitle = String.localizedStringWithFormat(format, thread.groupNameOrDefault)
        viewersSection.separatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing
        contents.add(viewersSection)

        let fullMembers = thread.groupMembership.fullMembers.filter { !$0.isLocalAddress }
        let totalViewersCount = fullMembers.count
        let maxViewersToShow = 6

        var viewersToRender = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerImplRef.sortSignalServiceAddresses(fullMembers, transaction: tx)
        }
        let hasMoreViewers = !isShowingAllViewers && viewersToRender.count > maxViewersToShow
        if hasMoreViewers {
            viewersToRender = Array(viewersToRender.prefix(maxViewersToShow - 1))
        }

        for viewerAddress in viewersToRender {
            viewersSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let cell = self?.tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                    owsFailDebug("Missing cell.")
                    return UITableViewCell()
                }

                SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    let configuration = ContactCellConfiguration(address: viewerAddress, localUserDisplayMode: .asLocalUser)
                    cell.configure(configuration: configuration, transaction: transaction)
                }

                return cell
            }, actionBlock: { [weak self] in
                self?.didSelectViewer(viewerAddress)
            }))
        }

        if hasMoreViewers {
            let expandedViewerIndices = (viewersToRender.count..<totalViewersCount).map {
                IndexPath(row: $0, section: contents.sections.count - 1)
            }

            viewersSection.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    let iconView = OWSTableItem.buildIconInCircleView(
                        icon: .groupInfoShowAllMembers,
                        iconSize: AvatarBuilder.smallAvatarSizePoints,
                        innerIconSize: 20,
                        iconTintColor: Theme.primaryTextColor
                    )

                    let rowLabel = UILabel()
                    rowLabel.text = CommonStrings.seeAllButton
                    rowLabel.textColor = Theme.primaryTextColor
                    rowLabel.font = OWSTableItem.primaryLabelFont
                    rowLabel.lineBreakMode = .byTruncatingTail

                    let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                    contentRow.spacing = ContactCellView.avatarTextHSpacing

                    cell.contentView.addSubview(contentRow)
                    contentRow.autoPinWidthToSuperviewMargins()
                    contentRow.autoPinHeightToSuperview(withMargin: 7)

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showAllViewers(revealingIndices: expandedViewerIndices)
                }
            ))
        }

        let deleteSection = OWSTableSection()
        contents.add(deleteSection)
        deleteSection.add(.actionItem(
            withText: OWSLocalizedString(
                "GROUP_STORY_SETTINGS_DELETE_BUTTON",
                comment: "Button to delete the story on the 'group story settings' view"
            ),
            textColor: .ows_accentRed,
            accessibilityIdentifier: nil,
            actionBlock: { [weak self] in
                self?.deleteStoryWithConfirmation()
            }))
    }

    private func deleteStoryWithConfirmation() {
        let format = OWSLocalizedString(
            "GROUP_STORY_SETTINGS_DELETE_CONFIRMATION_FORMAT",
            comment: "Action sheet title confirming deletion of a group story on the 'group story settings' view. Embeds {{ group name }}"
        )
        let actionSheet = ActionSheetController(
            message: String.localizedStringWithFormat(format, thread.groupNameOrDefault)
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "GROUP_STORY_SETTINGS_DELETE_BUTTON",
                comment: "Button to delete the story on the 'group story settings' view"
            ),
            style: .destructive,
            handler: { [weak self] _ in
                guard let self = self else { return }
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    self.thread.updateWithStorySendEnabled(false, transaction: transaction)
                }
                self.navigationController?.popViewController(animated: true)
            })
        )
        presentActionSheet(actionSheet)
    }

    private func showAllViewers(revealingIndices: [IndexPath]) {
        isShowingAllViewers = true

        if let firstIndex = revealingIndices.first {
            tableView.beginUpdates()

            // Delete the "See All" row.
            tableView.deleteRows(at: [IndexPath(row: firstIndex.row, section: firstIndex.section)], with: .top)

            // Insert the new rows.
            tableView.insertRows(at: revealingIndices, with: .top)

            updateTableContents(shouldReload: false)
            tableView.endUpdates()
        } else {
            updateTableContents()
        }
    }

    private func didSelectViewer(_ address: SignalServiceAddress) {
        // No need to share spoiler state; just start fresh.
        ProfileSheetSheetCoordinator(
            address: address,
            groupViewHelper: nil,
            spoilerState: SpoilerRenderState()
        )
        .presentAppropriateSheet(from: self)
    }
}
