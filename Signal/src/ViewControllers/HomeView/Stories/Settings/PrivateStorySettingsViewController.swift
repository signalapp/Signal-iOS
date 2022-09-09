//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalUI

class PrivateStorySettingsViewController: OWSTableViewController2 {
    let thread: TSPrivateStoryThread

    init(thread: TSPrivateStoryThread) {
        self.thread = thread
        super.init()
    }

    @objc
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarButtons()
        updateTableContents()
    }

    private func updateBarButtons() {
        title = thread.name

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .edit,
            target: self,
            action: #selector(editPressed)
        )
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

        let nameSection = OWSTableSection()
        contents.addSection(nameSection)
        nameSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true

            let iconView = OWSTableItem.buildIconInCircleView(
                icon: .settingsPrivateStory,
                iconSize: AvatarBuilder.smallAvatarSizePoints,
                innerIconSize: 24,
                iconTintColor: Theme.primaryTextColor
            )

            let rowLabel = UILabel()
            rowLabel.text = self?.thread.name
            rowLabel.textColor = Theme.primaryTextColor
            rowLabel.font = OWSTableItem.primaryLabelFont
            rowLabel.lineBreakMode = .byTruncatingTail

            let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
            contentRow.spacing = ContactCellView.avatarTextHSpacing

            cell.contentView.addSubview(contentRow)
            contentRow.autoPinWidthToSuperviewMargins()
            contentRow.autoPinHeightToSuperview(withMargin: 7)

            return cell
        }) { [weak self] in
            self?.editPressed()
        })

        let viewersSection = OWSTableSection()
        viewersSection.headerTitle = NSLocalizedString(
            "PRIVATE_STORY_SETTINGS_WHO_CAN_SEE_THIS_HEADER",
            comment: "Section header for the 'viewers' section on the 'private story settings' view"
        )
        viewersSection.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing))
        contents.addSection(viewersSection)

        // "Add Viewers" cell.
        viewersSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true

            let iconView = OWSTableItem.buildIconInCircleView(
                icon: .settingsAddMembers,
                iconSize: AvatarBuilder.smallAvatarSizePoints,
                innerIconSize: 24,
                iconTintColor: Theme.primaryTextColor
            )

            let rowLabel = UILabel()
            rowLabel.text = NSLocalizedString(
                "PRIVATE_STORY_SETTINGS_ADD_VIEWER_BUTTON",
                comment: "Button to add a new viewer on the 'private story settings' view"
            )
            rowLabel.textColor = Theme.primaryTextColor
            rowLabel.font = OWSTableItem.primaryLabelFont
            rowLabel.lineBreakMode = .byTruncatingTail

            let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
            contentRow.spacing = ContactCellView.avatarTextHSpacing

            cell.contentView.addSubview(contentRow)
            contentRow.autoPinWidthToSuperviewMargins()
            contentRow.autoPinHeightToSuperview(withMargin: 7)

            return cell
        }) { [weak self] in
            self?.showAddViewerView()
        })

        let totalViewersCount = thread.addresses.count
        let maxViewersToShow = 6

        var viewersToRender = databaseStorage.read {
            self.contactsManagerImpl.sortSignalServiceAddresses(
                thread.addresses,
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

        let repliesSection = OWSTableSection()
        repliesSection.headerTitle = StoryStrings.repliesAndReactionsHeader
        repliesSection.footerTitle = StoryStrings.repliesAndReactionsFooter
        contents.addSection(repliesSection)

        repliesSection.add(.switch(
            withText: StoryStrings.repliesAndReactionsToggle,
            isOn: { [thread] in thread.allowsReplies },
            target: self,
            selector: #selector(didToggleReplies(_:))
        ))

        let deleteSection = OWSTableSection()
        contents.addSection(deleteSection)
        deleteSection.add(.actionItem(
            withText: NSLocalizedString(
                "PRIVATE_STORY_SETTINGS_DELETE_BUTTON",
                comment: "Button to delete the story on the 'private story settings' view"
            ),
            textColor: .ows_accentRed,
            accessibilityIdentifier: nil,
            actionBlock: { [weak self] in
                self?.deleteStoryWithConfirmation()
            }))
    }

    private func deleteStoryWithConfirmation() {
        guard let dlistIdentifier = thread.distributionListIdentifier else {
            return owsFailDebug("Missing dlist identifier for thread \(thread.uniqueId)")
        }
        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "PRIVATE_STORY_SETTINGS_DELETE_CONFIRMATION",
                comment: "Action sheet title confirming deletion of a private story on the 'private story settings' view"
            )
        ) { _ in
            self.databaseStorage.write { transaction in
                self.thread.anyRemove(transaction: transaction)
                TSPrivateStoryThread.recordDeletedAtTimestamp(
                    Date.ows_millisecondTimestamp(),
                    forDistributionListIdentifer: dlistIdentifier,
                    transaction: transaction
                )
            }
            Self.storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: [dlistIdentifier])
            self.navigationController?.popViewController(animated: true)
        }
    }

    private func showAddViewerView() {
        let vc = PrivateStoryAddRecipientsSettingsViewController(thread: thread)
        navigationController?.pushViewController(vc, animated: true)
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
        let format = NSLocalizedString(
            "PRIVATE_STORY_SETTINGS_REMOVE_VIEWER_TITLE_FORMAT",
            comment: "Action sheet title prompting to remove a viewer from a story on the 'private story settings' view. Embeds {{ viewer name }}"
        )

        let actionSheet = ActionSheetController(
            title: String.localizedStringWithFormat(format, Self.contactsManager.displayName(for: address)),
            message: NSLocalizedString(
                "PRIVATE_STORY_SETTINGS_REMOVE_VIEWER_DESCRIPTION",
                comment: "Action sheet description prompting to remove a viewer from a story on the 'private story settings' view."
            )
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(.init(title: NSLocalizedString(
            "PRIVATE_STORY_SETTINGS_REMOVE_BUTTON",
            comment: "Action sheet button to remove a viewer from a story on the 'private story settings' view."
        ), style: .destructive, handler: { _ in
            self.databaseStorage.write { transaction in
                self.thread.updateWithStoryViewMode(
                    .explicit,
                    addresses: self.thread.addresses.filter { $0 != address },
                    updateStorageService: true,
                    transaction: transaction
                )
            }
            self.updateTableContents()
        }))

        presentActionSheet(actionSheet)
    }

    @objc
    func editPressed() {
        let vc = PrivateStoryNameSettingsViewController(thread: thread) { [weak self] in
            self?.title = self?.thread.name
            self?.updateTableContents()
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    @objc
    func didToggleReplies(_ toggle: UISwitch) {
        guard thread.allowsReplies != toggle.isOn else { return }
        databaseStorage.write { transaction in
            thread.updateWithAllowsReplies(toggle.isOn, updateStorageService: true, transaction: transaction)
        }
    }
}
