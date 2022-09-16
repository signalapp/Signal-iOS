//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalUI

class GroupStorySettingsViewController: OWSTableViewController2 {
    let thread: TSGroupThread
    let contextButton = ContextMenuButton()

    init(thread: TSGroupThread) {
        self.thread = thread
        super.init()
    }

    @objc
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
        updateTableContents()
    }

    override func applyTheme() {
        super.applyTheme()

        contextButton.tintColor = Theme.primaryIconColor
    }

    private func updateBarButtons() {
        title = thread.groupNameOrDefault

        contextButton.setImage(Theme.iconImage(.more24).withRenderingMode(.alwaysTemplate), for: .normal)
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.contextMenu = .init([
            .init(
                title: NSLocalizedString(
                    "STORIES_GO_TO_CHAT_ACTION",
                    comment: "Context menu action to open the chat associated with the selected story"
                ),
                image: Theme.iconImage(.open24),
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    self.dismiss(animated: true) {
                        Self.signalApp.presentConversation(for: self.thread, action: .compose, animated: true)
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
        viewersSection.headerTitle = NSLocalizedString(
            "GROUP_STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
            comment: "Section header for the 'viewers' section on the 'group story settings' view"
        )
        let format = NSLocalizedString(
            "GROUP_STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER_FORMAT",
            comment: "Section footer for the 'viewers' section on the 'group story settings' view. Embeds {{ group name }}"
        )
        viewersSection.footerTitle = String.localizedStringWithFormat(format, thread.groupNameOrDefault)
        viewersSection.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing))
        contents.addSection(viewersSection)

        let totalViewersCount = thread.groupMembership.fullMembers.count
        let maxViewersToShow = 6

        var viewersToRender = databaseStorage.read {
            self.contactsManagerImpl.sortSignalServiceAddresses(
                Array(thread.groupMembership.fullMembers),
                transaction: $0
            )
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

                Self.databaseStorage.read { transaction in
                    let configuration = ContactCellConfiguration(address: viewerAddress, localUserDisplayMode: .asLocalUser)
                    cell.configure(configuration: configuration, transaction: transaction)
                }

                return cell
            }) { [weak self] in
                self?.didSelectViewer(viewerAddress)
            })
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
                        icon: .settingsShowAllMembers,
                        iconSize: AvatarBuilder.smallAvatarSizePoints,
                        innerIconSize: 24,
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
        contents.addSection(deleteSection)
        deleteSection.add(.actionItem(
            withText: NSLocalizedString(
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
        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "GROUP_STORY_SETTINGS_DELETE_CONFIRMATION",
                comment: "Action sheet title confirming deletion of a group story on the 'group story settings' view"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            self.databaseStorage.write { transaction in
                self.thread.updateWithStorySendEnabled(false, transaction: transaction)
            }
            self.navigationController?.popViewController(animated: true)
        }
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
        let sheet = MemberActionSheet(address: address, groupViewHelper: nil)
        present(sheet, animated: true)
    }
}
