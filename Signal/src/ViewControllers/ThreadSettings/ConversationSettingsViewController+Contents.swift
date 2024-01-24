//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI
import UIKit

extension ConversationSettingsViewController {

    // MARK: - Helpers

    private var iconSpacingSmall: CGFloat {
        return ContactCellView.avatarTextHSpacing
    }

    private var iconSpacingLarge: CGFloat {
        return OWSTableItem.iconSpacing
    }

    private var isContactThread: Bool {
        return !thread.isGroupThread
    }

    private var hasExistingSystemContact: Bool {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return false
        }
        return databaseStorage.read { transaction in
            contactsManagerImpl.isSystemContact(address: contactThread.contactAddress, transaction: transaction)
        }
    }

    // MARK: - Table

    func updateTableContents(shouldReload: Bool = true) {

        let contents = OWSTableContents()

        let isNoteToSelf = thread.isNoteToSelf

        // Main section.
        let mainSection = OWSTableSection()
        let header = buildMainHeader()
        lastContentWidth = view.width
        mainSection.customHeaderView = header

        addDisappearingMessagesItem(to: mainSection)
        addColorAndWallpaperSettingsItem(to: mainSection)
        if !isNoteToSelf { addSoundAndNotificationSettingsItem(to: mainSection) }
        addSystemContactItemIfNecessary(to: mainSection)
        addSafetyNumberItemIfNecessary(to: mainSection)

        contents.add(mainSection)

        addAllMediaSectionIfNecessary(to: contents)
        addBadgesItemIfNecessary(to: contents)

        if let groupModel = currentGroupModel, !groupModel.isPlaceholder {
            contents.add(buildGroupMembershipSection(groupModel: groupModel, sectionIndex: contents.sections.count))

            if let groupModelV2 = groupModel as? TSGroupModelV2 {
                buildGroupSettingsSection(groupModelV2: groupModelV2, contents: contents)
            }
        } else if isContactThread, hasGroupThreads, !isNoteToSelf {
            contents.add(buildMutualGroupsSection(sectionIndex: contents.sections.count))
        }

        if
            !isNoteToSelf,
            !thread.isGroupV1Thread
        {
            contents.add(buildBlockAndLeaveSection())
        }

        if DebugFlags.internalSettings {
            contents.add(buildInternalSection())
        }

        let emptySection = OWSTableSection()
        emptySection.customFooterHeight = 24
        contents.add(emptySection)

        setContents(contents, shouldReload: shouldReload)

        updateNavigationBar()
    }

    private func addAllMediaSectionIfNecessary(to contents: OWSTableContents) {
        guard !recentMedia.isEmpty else { return }

        let section = OWSTableSection()
        section.headerTitle = MediaStrings.allMedia

        section.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                guard let self = self else { return cell }

                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.spacing = 5
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

                let totalSpacerSize = CGFloat(self.maximumRecentMedia - 1) * stackView.spacing
                let availableWidth = self.view.width - ((Self.cellHInnerMargin * 2) + self.cellOuterInsets.totalWidth + self.view.safeAreaInsets.totalWidth)
                let imageWidth = (availableWidth - totalSpacerSize) / CGFloat(self.maximumRecentMedia)

                for (attachmentStream, imageView) in self.recentMedia.orderedValues {
                    let button = OWSButton { [weak self] in
                        self?.showMediaPageView(for: attachmentStream)
                    }
                    stackView.addArrangedSubview(button)
                    button.autoSetDimensions(to: CGSize(square: imageWidth))

                    imageView.backgroundColor = .ows_middleGray

                    button.addSubview(imageView)
                    imageView.autoPinEdgesToSuperviewEdges()

                    let overlayView = UIView()
                    overlayView.isUserInteractionEnabled = false
                    overlayView.backgroundColor = .ows_blackAlpha05
                    button.addSubview(overlayView)
                    overlayView.autoPinEdgesToSuperviewEdges()
                }

                if self.recentMedia.count < self.maximumRecentMedia {
                    stackView.addArrangedSubview(.hStretchingSpacer())
                    stackView.autoPinEdge(toSuperviewMargin: .bottom)
                } else {
                    let seeAllLabel = UILabel()
                    seeAllLabel.textColor = Theme.primaryTextColor
                    seeAllLabel.font = OWSTableItem.primaryLabelFont
                    seeAllLabel.text = CommonStrings.seeAllButton

                    seeAllLabel.autoSetDimension(.height, toSize: OWSTableItem.primaryLabelFont.lineHeight)
                    cell.contentView.addSubview(seeAllLabel)
                    seeAllLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)
                    seeAllLabel.autoPinEdge(.top, to: .bottom, of: stackView, withOffset: 14)
                }

                return cell
            },
            actionBlock: { [weak self] in
                self?.showMediaGallery()
            }
        ))

        contents.add(section)
    }

    private func addBadgesItemIfNecessary(to contents: OWSTableContents) {
        guard !thread.isNoteToSelf, isContactThread else { return }
        guard let contactAddress = (thread as? TSContactThread)?.contactAddress else { return }

        let (visibleBadges, shortName) = databaseStorage.read { readTx -> ([OWSUserProfileBadgeInfo], String) in
            let profile = OWSUserProfile.getUserProfile(for: contactAddress, transaction: readTx)
            let shortName = contactsManager.shortDisplayName(for: contactAddress, transaction: readTx)
            return (profile?.visibleBadges ?? [], shortName)
        }
        guard !visibleBadges.isEmpty else { return }

        availableBadges = visibleBadges
        contents.add(.init(
            title: OWSLocalizedString("CONVERSATION_SETTINGS_BADGES_HEADER", comment: "Header title for a contact's badges in conversation settings"),
            items: [
                OWSTableItem(customCellBlock: { [weak self] in
                    let cell = OWSTableItem.newCell()
                    guard let self = self else { return cell }
                    let collectionView = BadgeCollectionView(dataSource: self)
                    collectionView.badgeSelectionMode = .detailsSheet(owner: .remote(shortName: shortName))

                    cell.contentView.addSubview(collectionView)
                    collectionView.autoPinEdgesToSuperviewMargins()

                    // Pre-layout the collection view so the UITableView caches the correct resolved
                    // autolayout height.
                    collectionView.layoutIfNeeded()

                    return cell
                }, actionBlock: nil)
            ],
            footerTitle: OWSLocalizedString("CONVERSATION_SETTINGS_BADGES_FOOTER", comment: "Footer string for a contact's badges in conversation settings"))
        )
    }

    private func addSafetyNumberItemIfNecessary(to section: OWSTableSection) {
        guard !thread.isNoteToSelf, !isGroupThread, thread.hasSafetyNumbers() else { return }

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            return OWSTableItem.buildDisclosureCell(name: OWSLocalizedString("VERIFY_PRIVACY",
                                                                            comment: "Label for button or row which allows users to verify the safety number of another user."),
                                                    icon: .contactInfoSafetyNumber,
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "safety_numbers"))
        },
        actionBlock: { [weak self] in
            self?.showVerificationView()
        }))
    }

    private func addSystemContactItemIfNecessary(to section: OWSTableSection) {
        guard !thread.isNoteToSelf, let contactThread = thread as? TSContactThread else { return }

        if hasExistingSystemContact {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildDisclosureCell(
                    name: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                        comment: "Indicates that user is in the system contacts list."
                    ),
                    icon: .contactInfoUserInContacts,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "is_in_contacts")
                )
            },
            actionBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return
                }
                self.presentCreateOrEditContactViewController(address: contactThread.contactAddress, editImmediately: false)
            }))
        } else {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                return OWSTableItem.buildDisclosureCell(
                    name: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                        comment: "button in conversation settings view."
                    ),
                    icon: .contactInfoAddToContacts,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "add_to_system_contacts")
                )
            },
            actionBlock: { [weak self] in
                self?.showAddToSystemContactsActionSheet(contactThread: contactThread)
            }))
        }
    }

    private func addColorAndWallpaperSettingsItem(to section: OWSTableSection) {
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsWallpaper,
                itemName: OWSLocalizedString(
                    "SETTINGS_ITEM_COLOR_AND_WALLPAPER",
                    comment: "Label for settings view that allows user to change the chat color and wallpaper."
                ),
                accessoryType: .disclosureIndicator,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "color_and_wallpaper")
            )
            return cell
        },
        actionBlock: { [weak self] in
            self?.showColorAndWallpaperSettingsView()
        }))
    }

    private func addSoundAndNotificationSettingsItem(to section: OWSTableSection) {
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsMessageSound,
                itemName: OWSLocalizedString(
                    "SOUND_AND_NOTIFICATION_SETTINGS",
                    comment: "table cell label in conversation settings"
                ),
                accessoryType: .disclosureIndicator,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "sound_and_notifications")
            )
            return cell
        },
        actionBlock: { [weak self] in
            self?.showSoundAndNotificationsSettingsView()
        }))
    }

    private func addDisappearingMessagesItem(to section: OWSTableSection) {

        let canEditConversationAttributes = self.canEditConversationAttributes
        let disappearingMessagesConfiguration = self.disappearingMessagesConfiguration
        let thread = self.thread

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildCell(
                    icon: disappearingMessagesConfiguration.isEnabled
                        ? .chatSettingsTimerOn
                        : .chatSettingsTimerOff,
                    itemName: OWSLocalizedString(
                        "DISAPPEARING_MESSAGES",
                        comment: "table cell label in conversation settings"
                    ),
                    accessoryText: disappearingMessagesConfiguration.isEnabled
                        ? DateUtil.formatDuration(seconds: disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
                        : CommonStrings.switchOff,
                    accessoryType: .disclosureIndicator,
                    customColor: canEditConversationAttributes ? nil : Theme.secondaryTextAndIconColor,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")
                )
                cell.isUserInteractionEnabled = canEditConversationAttributes
                return cell
            }, actionBlock: { [weak self] in
                let vc = DisappearingMessagesTimerSettingsViewController(
                    thread: thread,
                    configuration: disappearingMessagesConfiguration
                ) { configuration in
                    self?.disappearingMessagesConfiguration = configuration
                    self?.updateTableContents()
                    NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
    }

    private func buildBlockAndLeaveSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.footerTitle = isGroupThread
            ? OWSLocalizedString("CONVERSATION_SETTINGS_BLOCK_AND_LEAVE_SECTION_FOOTER",
                                comment: "Footer text for the 'block and leave' section of group conversation settings view.")
            : OWSLocalizedString("CONVERSATION_SETTINGS_BLOCK_AND_LEAVE_SECTION_CONTACT_FOOTER",
                                comment: "Footer text for the 'block and leave' section of contact conversation settings view.")

        if isGroupThread, isLocalUserFullOrInvitedMember {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildCell(
                    icon: .groupInfoLeaveGroup,
                    itemName: OWSLocalizedString(
                        "LEAVE_GROUP_ACTION",
                        comment: "table cell label in conversation settings"
                    ),
                    customColor: UIColor.ows_accentRed,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group")
                )
            },
            actionBlock: { [weak self] in
                self?.didTapLeaveGroup()
            }))
        }

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cellTitle: String
            var customColor: UIColor?
            if self.threadViewModel.isBlocked {
                cellTitle =
                    (self.thread.isGroupThread
                        ? OWSLocalizedString("CONVERSATION_SETTINGS_UNBLOCK_GROUP",
                                            comment: "Label for 'unblock group' action in conversation settings view.")
                        : OWSLocalizedString("CONVERSATION_SETTINGS_UNBLOCK_USER",
                                            comment: "Label for 'unblock user' action in conversation settings view."))
            } else {
                cellTitle =
                    (self.thread.isGroupThread
                        ? OWSLocalizedString("CONVERSATION_SETTINGS_BLOCK_GROUP",
                                            comment: "Label for 'block group' action in conversation settings view.")
                        : OWSLocalizedString("CONVERSATION_SETTINGS_BLOCK_USER",
                                            comment: "Label for 'block user' action in conversation settings view."))
                customColor = UIColor.ows_accentRed
            }
            let cell = OWSTableItem.buildCell(
                icon: .chatSettingsBlock,
                itemName: cellTitle,
                customColor: customColor,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "block")
            )
            return cell
        },
        actionBlock: { [weak self] in
            if self?.threadViewModel.isBlocked == true {
                self?.didTapUnblockThread()
            } else {
                self?.didTapBlockThread()
            }
        }))

        return section
    }

    private func buildInternalSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            return OWSTableItem.buildCell(
                icon: .settingsAdvanced,
                itemName: "Internal",
                accessoryType: .disclosureIndicator,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "internal")
            )
        },
        actionBlock: { [weak self] in
            self?.didTapInternalSettings()
        }))

        return section
    }

    private func accessoryLabel(forAccess access: GroupV2Access) -> String {
        switch access {
        case .any, .member:
            if access != .member {
                owsFailDebug("Invalid attributes access: \(access.rawValue)")
            }
            return OWSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_MEMBER",
                                             comment: "Label indicating that all group members can update the group's attributes: name, avatar, etc.")
        case .administrator:
            return OWSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_ADMINISTRATOR",
                                     comment: "Label indicating that only administrators can update the group's attributes: name, avatar, etc.")
        case .unknown, .unsatisfiable:
            owsFailDebug("Invalid access")
            return OWSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_NONE",
                                     comment: "Label indicating that no member can update the group's attributes: name, avatar, etc.")
        }
    }

    private func buildGroupMembershipSection(groupModel: TSGroupModel, sectionIndex: Int) -> OWSTableSection {
        let section = OWSTableSection()
        section.separatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        let groupMembership = groupModel.groupMembership

        // "Add Members" cell.
        if canEditConversationMembership {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = OWSTableItem.buildIconInCircleView(
                    icon: .groupInfoAddMembers,
                    iconSize: AvatarBuilder.smallAvatarSizePoints,
                    innerIconSize: 20,
                    iconTintColor: Theme.primaryTextColor
                )

                let rowLabel = UILabel()
                rowLabel.text = OWSLocalizedString("CONVERSATION_SETTINGS_ADD_MEMBERS",
                                                  comment: "Label for 'add members' button in conversation settings view.")
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacingSmall

                cell.contentView.addSubview(contentRow)
                contentRow.autoPinWidthToSuperviewMargins()
                contentRow.autoPinHeightToSuperview(withMargin: 7)

                return cell
            }, actionBlock: { [weak self] in
                                        self?.showAddMembersView()
            }))
        }

        let totalMemberCount = sortedGroupMembers.count

        let format = OWSLocalizedString("CONVERSATION_SETTINGS_MEMBERS_SECTION_TITLE_%d", tableName: "PluralAware",
                                       comment: "Format for the section title of the 'members' section in conversation settings view. Embeds: {{ the number of group members }}.")
        section.headerTitle = String.localizedStringWithFormat(format, totalMemberCount)

        var membersToRender = sortedGroupMembers

        let maxMembersToShow = 6
        let hasMoreMembers = !isShowingAllGroupMembers && membersToRender.count > maxMembersToShow
        if hasMoreMembers {
            membersToRender = Array(membersToRender.prefix(maxMembersToShow - 1))
        }

        for memberAddress in membersToRender {
            guard let verificationState = groupMemberStateMap[memberAddress] else {
                owsFailDebug("Missing verificationState.")
                continue
            }

            let isLocalUser = memberAddress.isLocalAddress
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let tableView = self.tableView
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                    owsFailDebug("Missing cell.")
                    return UITableViewCell()
                }

                Self.databaseStorage.read { transaction in
                    let configuration = ContactCellConfiguration(address: memberAddress, localUserDisplayMode: .asLocalUser)
                    let isGroupAdmin = groupMembership.isFullMemberAndAdministrator(memberAddress)
                    let isVerified = verificationState == .verified
                    let isNoLongerVerified = verificationState == .noLongerVerified
                    let isBlocked = self.blockingManager.isAddressBlocked(memberAddress, transaction: transaction)
                    if isGroupAdmin {
                        configuration.accessoryMessage = OWSLocalizedString("GROUP_MEMBER_ADMIN_INDICATOR",
                                                                           comment: "Label indicating that a group member is an admin.")
                    } else if isNoLongerVerified {
                        configuration.accessoryMessage = OWSLocalizedString("CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                                                                           comment: "An indicator that a contact is no longer verified.")
                    } else if isBlocked {
                        configuration.accessoryMessage = MessageStrings.conversationIsBlocked
                    }

                    if isLocalUser {
                        cell.selectionStyle = .none
                    } else {
                        cell.selectionStyle = .default
                    }

                    if isVerified {
                        configuration.useVerifiedSubtitle()
                    } else if !memberAddress.isLocalAddress,
                              let bioForDisplay = (Self.profileManagerImpl.profileBioForDisplay(for: memberAddress,
                                                                                                transaction: transaction)) {
                        configuration.attributedSubtitle = NSAttributedString(string: bioForDisplay)
                    } else {
                        owsAssertDebug(configuration.attributedSubtitle == nil)
                    }

                    cell.configure(configuration: configuration, transaction: transaction)
                }

                let cellName = "user.\(memberAddress.stringForDisplay)"
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: cellName)

                return cell
            }, actionBlock: { [weak self] in
                                        self?.didSelectGroupMember(memberAddress)
            }))
        }

        if hasMoreMembers {
            let offset = canEditConversationMembership ? 1 : 0
            let expandedMemberIndices = ((membersToRender.count + offset)..<(totalMemberCount + offset)).map {
                IndexPath(row: $0, section: sectionIndex)
            }

            section.add(OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }
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
                    contentRow.spacing = self.iconSpacingSmall

                    cell.contentView.addSubview(contentRow)
                    contentRow.autoPinWidthToSuperviewMargins()
                    contentRow.autoPinHeightToSuperview(withMargin: 7)

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showAllGroupMembers(revealingIndices: expandedMemberIndices)
                }
            ))
        }

        return section
    }

    private func buildGroupSettingsSection(
        groupModelV2: TSGroupModelV2,
        contents: OWSTableContents
    ) {
        let section = OWSTableSection()

        let groupLinkStatus = (groupModelV2.isGroupInviteLinkEnabled
                               ? CommonStrings.switchOn
                               : CommonStrings.switchOff)
        section.add(OWSTableItem.disclosureItem(
            icon: .groupInfoGroupLink,
            name: OWSLocalizedString(
                "CONVERSATION_SETTINGS_GROUP_LINK",
                comment: "Label for 'group link' action in conversation settings view."
            ),
            accessoryText: groupLinkStatus,
            accessibilityIdentifier: "conversation_settings_group_link",
            actionBlock: { [weak self] in
                self?.showGroupLinkView()
            })
        )

        let itemTitle = OWSLocalizedString("CONVERSATION_SETTINGS_MEMBER_REQUESTS_AND_INVITES",
                                          comment: "Label for 'member requests & invites' action in conversation settings view.")
        section.add(OWSTableItem.disclosureItem(
            icon: .groupInfoRequestAndInvites,
            name: itemTitle,
            accessoryText: OWSFormat.formatInt(groupModelV2.groupMembership.invitedOrRequestMembers.count),
            accessibilityIdentifier: "conversation_settings_requests_and_invites",
            actionBlock: { [weak self] in
                self?.showMemberRequestsAndInvitesView()
            })
        )

        if canEditPermissions {
            let itemTitle = OWSLocalizedString(
                "CONVERSATION_SETTINGS_PERMISSIONS",
                comment: "Label for 'permissions' action in conversation settings view."
            )
            section.add(OWSTableItem.disclosureItem(
                icon: .groupInfoPermissions,
                name: itemTitle,
                accessibilityIdentifier: "conversation_settings_permissions",
                actionBlock: { [weak self] in
                    self?.showPermissionsSettingsView()
                }
            ))
        }

        contents.add(section)
    }

    private func buildMutualGroupsSection(sectionIndex: Int) -> OWSTableSection {
        let section = OWSTableSection()
        section.separatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        // "Add to a Group" cell.
        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = OWSTableItem.buildIconInCircleView(
                    icon: .groupInfoAddMembers,
                    iconSize: AvatarBuilder.smallAvatarSizePoints,
                    innerIconSize: 20,
                    iconTintColor: Theme.primaryTextColor
                )

                let rowLabel = UILabel()
                rowLabel.text = OWSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacingSmall

                cell.contentView.addSubview(contentRow)
                contentRow.autoPinWidthToSuperviewMargins()
                contentRow.autoPinHeightToSuperview(withMargin: 7)

                return cell
            },
            actionBlock: { [weak self] in
                self?.showAddToGroupView()
            }
        ))

        if mutualGroupThreads.count > 0 {
            let headerFormat = OWSLocalizedString("CONVERSATION_SETTINGS_MUTUAL_GROUPS_SECTION_TITLE_%d", tableName: "PluralAware",
                                                 comment: "Format for the section title of the 'mutual groups' section in conversation settings view. Embeds: {{ the number of shared groups }}."
            )
            section.headerTitle = String.localizedStringWithFormat(headerFormat, mutualGroupThreads.count)
        } else {
            section.headerTitle = OWSLocalizedString("CONVERSATION_SETTINGS_NO_MUTUAL_GROUPS_SECTION_TITLE",
                                                    comment: "Section title of the 'mutual groups' section in conversation settings view when the contact shares no mutual groups."
            )
        }

        let maxGroupsToShow = 6
        let hasMoreGroups = !isShowingAllMutualGroups && mutualGroupThreads.count > maxGroupsToShow
        let groupThreadsToRender: [TSGroupThread]
        if hasMoreGroups {
            groupThreadsToRender = Array(mutualGroupThreads.prefix(maxGroupsToShow - 1))
        } else {
            groupThreadsToRender = mutualGroupThreads
        }

        for groupThread in groupThreadsToRender {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = GroupTableViewCell()
                    cell.configure(thread: groupThread)
                    return cell
                },
                actionBlock: {
                    SignalApp.shared.presentConversationForThread(groupThread, animated: true)
                }
            ))
        }

        if hasMoreGroups {
            let expandedGroupIndices = ((groupThreadsToRender.count + 1)..<(mutualGroupThreads.count + 1)).map {
                IndexPath(row: $0, section: sectionIndex)
            }

            section.add(OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }
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
                    contentRow.spacing = self.iconSpacingSmall

                    cell.contentView.addSubview(contentRow)
                    contentRow.autoPinWidthToSuperviewMargins()
                    contentRow.autoPinHeightToSuperview(withMargin: 7)

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showAllMutualGroups(revealingIndices: expandedGroupIndices)
                }
            ))
        }

        return section
    }
}
