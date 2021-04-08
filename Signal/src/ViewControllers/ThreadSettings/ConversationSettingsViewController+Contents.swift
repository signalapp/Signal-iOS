//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

extension ConversationSettingsViewController {

    // MARK: - Helpers

    private var iconSpacingSmall: CGFloat {
        return kContactCellAvatarTextMargin
    }

    private var iconSpacingLarge: CGFloat {
        return OWSTableItem.iconSpacing
    }

    private var isContactThread: Bool {
        return !thread.isGroupThread
    }

    private var hasExistingContact: Bool {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return false
        }
        return contactsManagerImpl.hasSignalAccount(for: contactThread.contactAddress)
    }

    private func buildCell(name: String, icon: ThemeIcon,
                           disclosureIconColor: UIColor? = nil,
                           accessibilityIdentifier: String? = nil) -> UITableViewCell {
        let cell = OWSTableItem.buildCell(name: name, icon: icon, accessibilityIdentifier: accessibilityIdentifier)
        if let disclosureIconColor = disclosureIconColor {
            let accessoryView = OWSColorPickerAccessoryView(color: disclosureIconColor)
            accessoryView.sizeToFit()
            cell.accessoryView = accessoryView
        }
        return cell
    }

    // MARK: - Table

    func updateTableContents() {

        let contents = OWSTableContents()

        let isNoteToSelf = thread.isNoteToSelf

        // Main section.
        let mainSection = OWSTableSection()
        let header = buildMainHeader()
        lastContentWidth = view.width
        mainSection.customHeaderView = header

        addDisappearingMessagesItem(to: mainSection)
        addWallpaperSettingsItem(to: mainSection)
        if !isNoteToSelf { addSoundAndNotificationSettingsItem(to: mainSection) }
        addSystemContactItemIfNecessary(to: mainSection)
        addSafetyNumberItemIfNecessary(to: mainSection)

        if DebugFlags.shouldShowColorPicker {
            addColorPickerItems(to: mainSection)
        }

        contents.addSection(mainSection)

        addAllMediaSectionIfNecessary(to: contents)

        if let groupModel = currentGroupModel, !groupModel.isPlaceholder {
            contents.addSection(buildGroupMembershipSection(groupModel: groupModel))

            if let groupModelV2 = groupModel as? TSGroupModelV2 {
                buildGroupSettingsSection(groupModelV2: groupModelV2, contents: contents)
            }
        } else if isContactThread, hasGroupThreads {
            contents.addSection(buildMutualGroupsSection())
        }

        if !isNoteToSelf {
            contents.addSection(buildBlockAndLeaveSection())
        }

        let emptySection = OWSTableSection()
        emptySection.customFooterHeight = 24
        contents.addSection(emptySection)

        self.contents = contents

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

                cell.selectionStyle = .none

                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.spacing = 5
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

                let spacerWidth = CGFloat(self.maximumRecentMedia - 1) * stackView.spacing
                let imageWidth = ((self.view.width - (Self.cellHInnerMargin + Self.cellHOuterMargin)) / CGFloat(self.maximumRecentMedia)) - spacerWidth

                for (attachmentStream, imageView) in self.recentMedia.orderedValues {
                    let button = OWSButton { [weak self] in
                        self?.showMediaPageView(for: attachmentStream)
                    }
                    stackView.addArrangedSubview(button)

                    imageView.backgroundColor = Theme.middleGrayColor
                    imageView.autoSetDimensions(to: CGSize(square: imageWidth))

                    button.addSubview(imageView)
                    imageView.autoPinEdgesToSuperviewEdges()
                }

                if self.recentMedia.count < self.maximumRecentMedia {
                    stackView.addArrangedSubview(.hStretchingSpacer())
                    stackView.autoPinEdge(toSuperviewMargin: .bottom)
                } else {
                    let seeAllButton = OWSButton { [weak self] in
                        self?.showMediaGallery()
                    }
                    seeAllButton.setTitle(CommonStrings.seeAllButton, for: .normal)
                    seeAllButton.setTitleColor(Theme.primaryTextColor, for: .normal)
                    seeAllButton.contentHorizontalAlignment = .leading
                    seeAllButton.titleLabel?.font = OWSTableItem.primaryLabelFont
                    seeAllButton.autoSetDimension(.height, toSize: OWSTableItem.primaryLabelFont.lineHeight)
                    cell.contentView.addSubview(seeAllButton)
                    seeAllButton.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)
                    seeAllButton.autoPinEdge(.top, to: .bottom, of: stackView, withOffset: 14)
                }

                return cell
            },
            actionBlock: {}
        ))

        contents.addSection(section)
    }

    private func addBasicItems(to section: OWSTableSection) {
        let isNoteToSelf = thread.isNoteToSelf

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }
            return OWSTableItem.buildDisclosureCell(name: MediaStrings.allMedia,
                                                    icon: .settingsAllMedia,
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "all_media"))
            },
                                 actionBlock: { [weak self] in
                                    self?.showMediaGallery()
        }))

        if !groupViewHelper.isBlockedByMigration {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let title = NSLocalizedString("CONVERSATION_SETTINGS_SEARCH",
                                              comment: "Table cell label in conversation settings which returns the user to the conversation with 'search mode' activated")
                return OWSTableItem.buildDisclosureCell(name: title,
                                                        icon: .settingsSearch,
                                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "search"))
            },
            actionBlock: { [weak self] in
                self?.tappedConversationSearch()
            }))
        }

        // Indicate if the user is in the system contacts
        if !isNoteToSelf && !isGroupThread && hasExistingContact {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildDisclosureCell(name: NSLocalizedString(
                    "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                    comment: "Indicates that user is in the system contacts list."),
                                                        icon: .settingsUserInContacts,
                                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "is_in_contacts"))
                },
                                     actionBlock: { [weak self] in
                                        guard let self = self else {
                                            owsFailDebug("Missing self")
                                            return
                                        }
                                        if self.contactsManagerImpl.supportsContactEditing {
                                            self.presentContactViewController()
                                        }
            }))
        }
    }

    private func addSafetyNumberItemIfNecessary(to section: OWSTableSection) {
        guard !thread.isNoteToSelf, !isGroupThread, thread.hasSafetyNumbers() else { return }

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            return OWSTableItem.buildDisclosureCell(name: NSLocalizedString("VERIFY_PRIVACY",
                                                                            comment: "Label for button or row which allows users to verify the safety number of another user."),
                                                    icon: .settingsViewSafetyNumber,
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "safety_numbers"))
        },
        actionBlock: { [weak self] in
            self?.showVerificationView()
        }))
    }

    private func addSystemContactItemIfNecessary(to section: OWSTableSection) {
        guard !thread.isNoteToSelf,
              let contactThread = thread as? TSContactThread,
              contactsManagerImpl.supportsContactEditing else { return }

        if hasExistingContact {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildDisclosureCell(name: NSLocalizedString(
                                                            "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                                                            comment: "Indicates that user is in the system contacts list."),
                                                        icon: .settingsUserInContacts,
                                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "is_in_contacts"))
            },
            actionBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return
                }
                if self.contactsManagerImpl.supportsContactEditing {
                    self.presentContactViewController()
                }
            }))
        } else {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                return OWSTableItem.buildDisclosureCell(name: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                                                                                comment: "button in conversation settings view."),
                                                        icon: .settingsAddToContacts,
                                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "add_to_system_contacts"))
            },
            actionBlock: { [weak self] in
                self?.showAddToSystemContactsActionSheet(contactThread: contactThread)
            }))
        }
    }

    private func addWallpaperSettingsItem(to section: OWSTableSection) {
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cell = OWSTableItem.buildCellWithAccessoryLabel(
                icon: .settingsWallpaper,
                itemName: NSLocalizedString("SETTINGS_ITEM_WALLPAPER",
                                            comment: "Label for settings view that allows user to change the wallpaper."),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "wallpaper")
            )
            return cell
        },
        actionBlock: { [weak self] in
            self?.showWallpaperSettingsView()
        }))
    }

    private func addSoundAndNotificationSettingsItem(to section: OWSTableSection) {
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cell = OWSTableItem.buildCellWithAccessoryLabel(
                icon: .settingsMessageSound,
                itemName: NSLocalizedString(
                    "SOUND_AND_NOTIFICATION_SETTINGS",
                    comment: "table cell label in conversation settings"
                ),
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

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildIconNameCell(
                    icon: disappearingMessagesConfiguration.isEnabled
                        ? .settingsTimer
                        : .settingsTimerDisabled,
                    itemName: NSLocalizedString(
                        "DISAPPEARING_MESSAGES",
                        comment: "table cell label in conversation settings"
                    ),
                    accessoryText: disappearingMessagesConfiguration.isEnabled
                        ? NSString.formatDurationSeconds(disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
                        : CommonStrings.switchOff,
                    accessoryType: .disclosureIndicator,
                    accessoryImage: nil,
                    customColor: canEditConversationAttributes ? nil : Theme.secondaryTextAndIconColor,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")
                )
                cell.isUserInteractionEnabled = canEditConversationAttributes
                return cell
            }, actionBlock: { [weak self] in
                let vc = DisappearingMessagesTimerSettingsViewController(configuration: disappearingMessagesConfiguration) { configuration in
                    self?.disappearingMessagesConfiguration = configuration
                    self?.updateTableContents()
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
    }

    private func addColorPickerItems(to section: OWSTableSection) {
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let colorName = self.thread.conversationColorName
            let currentColor = OWSConversationColor.conversationColorOrDefault(colorName: colorName).themeColor
            let title = NSLocalizedString("CONVERSATION_SETTINGS_CONVERSATION_COLOR",
                                          comment: "Label for table cell which leads to picking a new conversation color")
            return self.buildCell(name: title,
                                  icon: .settingsColorPalette,
                                  disclosureIconColor: currentColor,
                                  accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "conversation_color"))
            },
                                 actionBlock: { [weak self] in
                                    self?.showColorPicker()
        }))
    }

    private func buildBlockAndLeaveSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.footerTitle = isGroupThread
            ? NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_AND_LEAVE_SECTION_FOOTER",
                                comment: "Footer text for the 'block and leave' section of group conversation settings view.")
            : NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_AND_LEAVE_SECTION_CONTACT_FOOTER",
                                comment: "Footer text for the 'block and leave' section of contact conversation settings view.")

        if isGroupThread, isLocalUserFullOrInvitedMember {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildIconNameCell(icon: .settingsLeaveGroup,
                                                      itemName: NSLocalizedString("LEAVE_GROUP_ACTION",
                                                                                  comment: "table cell label in conversation settings"),
                                                      customColor: UIColor.ows_accentRed,
                                                      accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group"))
                },
                                     actionBlock: { [weak self] in
                                        self?.didTapLeaveGroup()
            }))
        }

        let isCurrentlyBlocked = blockingManager.isThreadBlocked(thread)

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cellTitle: String
            var customColor: UIColor?
            if isCurrentlyBlocked {
                cellTitle =
                    (self.thread.isGroupThread
                        ? NSLocalizedString("CONVERSATION_SETTINGS_UNBLOCK_GROUP",
                                            comment: "Label for 'unblock group' action in conversation settings view.")
                        : NSLocalizedString("CONVERSATION_SETTINGS_UNBLOCK_USER",
                                            comment: "Label for 'unblock user' action in conversation settings view."))
            } else {
                cellTitle =
                    (self.thread.isGroupThread
                        ? NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_GROUP",
                                            comment: "Label for 'block group' action in conversation settings view.")
                        : NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_USER",
                                            comment: "Label for 'block user' action in conversation settings view."))
                customColor = UIColor.ows_accentRed
            }
            let cell = OWSTableItem.buildIconNameCell(icon: .settingsBlock,
                                                      itemName: cellTitle,
                                                      customColor: customColor,
                                                      accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "block"))
            return cell
            },
                                 actionBlock: { [weak self] in
                                    if isCurrentlyBlocked {
                                        self?.didTapUnblockGroup()
                                    } else {
                                        self?.didTapBlockGroup()
                                    }
        }))

        return section
    }

    private func accessoryLabel(forAccess access: GroupV2Access) -> String {
        switch access {
        case .any, .member:
            if access != .member {
                owsFailDebug("Invalid attributes access: \(access.rawValue)")
            }
            return NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_MEMBER",
                                             comment: "Label indicating that all group members can update the group's attributes: name, avatar, etc.")
        case .administrator:
            return NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_ADMINISTRATOR",
                                     comment: "Label indicating that only administrators can update the group's attributes: name, avatar, etc.")
        case .unknown, .unsatisfiable:
            owsFailDebug("Invalid access")
            return NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_NONE",
                                     comment: "Label indicating that no member can update the group's attributes: name, avatar, etc.")
        }
    }

    private func buildGroupMembershipSection(groupModel: TSGroupModel) -> OWSTableSection {
        let section = OWSTableSection()
        section.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(kSmallAvatarSize) + kContactCellAvatarTextMargin))

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return section
        }
        let helper = contactsViewHelper

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

                let iconView = OWSTableItem.buildIconInCircleView(icon: .settingsAddMembers,
                                                                  iconSize: kSmallAvatarSize,
                                                                  innerIconSize: 24,
                                                                  iconTintColor: Theme.primaryTextColor)

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("CONVERSATION_SETTINGS_ADD_MEMBERS",
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
                }) { [weak self] in
                                        self?.showAddMembersView()
            })
        }

        let groupMembership = groupModel.groupMembership
        let allMembers = groupMembership.fullMembers
        var allMembersSorted = [SignalServiceAddress]()
        var verificationStateMap = [SignalServiceAddress: OWSVerificationState]()
        databaseStorage.uiRead { transaction in
            for memberAddress in allMembers {
                verificationStateMap[memberAddress] = self.identityManager.verificationState(for: memberAddress,
                                                                                             transaction: transaction)
            }
            allMembersSorted = self.contactsManagerImpl.sortSignalServiceAddresses(Array(allMembers),
                                                                                   transaction: transaction)
        }

        var membersToRender = [SignalServiceAddress]()
        if groupMembership.isFullMember(localAddress) {
            // Make sure local user is first.
            membersToRender.insert(localAddress, at: 0)
        }
        // Admin users are second.
        let adminMembers = allMembersSorted.filter { $0 != localAddress && groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += adminMembers
        // Non-admin users are third.
        let nonAdminMembers = allMembersSorted.filter { $0 != localAddress && !groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += nonAdminMembers

        if membersToRender.count > 1 {
            let headerFormat = NSLocalizedString("CONVERSATION_SETTINGS_MEMBERS_SECTION_TITLE_FORMAT",
                                                 comment: "Format for the section title of the 'members' section in conversation settings view. Embeds: {{ the number of group members }}.")
            section.headerTitle = String(format: headerFormat,
                                         OWSFormat.formatInt(membersToRender.count))
        } else {
            section.headerTitle = NSLocalizedString("CONVERSATION_SETTINGS_MEMBERS_SECTION_TITLE",
                                                    comment: "Section title of the 'members' section in conversation settings view.")
        }

        let maxMembersToShow = 6
        let hasMoreMembers = !isShowingAllGroupMembers && membersToRender.count > maxMembersToShow
        if hasMoreMembers {
            membersToRender = Array(membersToRender.prefix(maxMembersToShow - 1))
        }

        for memberAddress in membersToRender {
            guard let verificationState = verificationStateMap[memberAddress] else {
                owsFailDebug("Missing verificationState.")
                continue
            }

            let isLocalUser = memberAddress == localAddress
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = ContactTableViewCell()

                let isGroupAdmin = groupMembership.isFullMemberAndAdministrator(memberAddress)
                let isVerified = verificationState == .verified
                let isNoLongerVerified = verificationState == .noLongerVerified
                let isBlocked = helper.isSignalServiceAddressBlocked(memberAddress)
                if isGroupAdmin {
                    cell.setAccessoryMessage(NSLocalizedString("GROUP_MEMBER_ADMIN_INDICATOR",
                                                               comment: "Label indicating that a group member is an admin."))
                } else if isNoLongerVerified {
                    cell.setAccessoryMessage(NSLocalizedString("CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                                                               comment: "An indicator that a contact is no longer verified."))
                } else if isBlocked {
                    cell.setAccessoryMessage(MessageStrings.conversationIsBlocked)
                }

                if isLocalUser {
                    // Use a custom avatar to avoid using the "note to self" icon.
                    let customAvatar = Self.profileManagerImpl.localProfileAvatarImage() ?? OWSContactAvatarBuilder(forLocalUserWithDiameter: kSmallAvatarSize).buildDefaultImage()
                    cell.setCustomAvatar(customAvatar)
                    cell.setCustomName(NSLocalizedString("GROUP_MEMBER_LOCAL_USER",
                                                         comment: "Label indicating the local user."))
                    cell.selectionStyle = .none
                } else {
                    cell.selectionStyle = .default
                }

                cell.configureWithSneakyTransaction(recipientAddress: memberAddress)

                if isVerified {
                    cell.setAttributedSubtitle(cell.verifiedSubtitle())
                } else if !memberAddress.isLocalAddress,
                          let bioForDisplay = (Self.databaseStorage.uiRead { transaction in
                    Self.profileManagerImpl.profileBioForDisplay(for: memberAddress, transaction: transaction)
                }) {
                    cell.setAttributedSubtitle(NSAttributedString(string: bioForDisplay))
                } else {
                    cell.setAttributedSubtitle(nil)
                }

                let cellName = "user.\(memberAddress.stringForDisplay)"
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: cellName)

                return cell
                }) { [weak self] in
                                        self?.didSelectGroupMember(memberAddress)
            })
        }

        if hasMoreMembers {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = OWSTableItem.buildIconInCircleView(icon: .settingsShowAllMembers,
                                                                  iconSize: kSmallAvatarSize,
                                                                  innerIconSize: 24,
                                                                  iconTintColor: Theme.primaryTextColor)

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
                }) { [weak self] in
                                        self?.showAllGroupMembers()
            })
        }

        return section
    }

    private func buildGroupSettingsSection(
        groupModelV2: TSGroupModelV2,
        contents: OWSTableContents
    ) {
        let section = OWSTableSection()

        if RemoteConfig.groupsV2InviteLinks {
            let groupLinkStatus = (groupModelV2.isGroupInviteLinkEnabled
                ? CommonStrings.switchOn
                : CommonStrings.switchOff)
            section.add(OWSTableItem.disclosureItem(icon: .settingsLink,
                                                    name: NSLocalizedString("CONVERSATION_SETTINGS_GROUP_LINK",
                                                                            comment: "Label for 'group link' action in conversation settings view."),
                                                    accessoryText: groupLinkStatus,
                                                    accessibilityIdentifier: "conversation_settings_group_link",
                                                    actionBlock: { [weak self] in
                                                        self?.showGroupLinkView()
            }))
        }

        let itemTitle = (RemoteConfig.groupsV2InviteLinks
            ? NSLocalizedString("CONVERSATION_SETTINGS_MEMBER_REQUESTS_AND_INVITES",
                                comment: "Label for 'member requests & invites' action in conversation settings view.")
            : NSLocalizedString("CONVERSATION_SETTINGS_MEMBER_INVITES",
                                comment: "Label for 'member invites' action in conversation settings view."))
        section.add(OWSTableItem.disclosureItem(icon: .settingsViewRequestAndInvites,
                                                name: itemTitle,
                                                accessoryText: OWSFormat.formatInt(groupModelV2.groupMembership.invitedOrRequestMembers.count),
                                                accessibilityIdentifier: "conversation_settings_requests_and_invites",
                                                actionBlock: { [weak self] in
                                                    self?.showMemberRequestsAndInvitesView()
        }))

        if canEditConversationAccess {
            let itemTitle = NSLocalizedString(
                "CONVERSATION_SETTINGS_PERMISSIONS",
                comment: "Label for 'permissions' action in conversation settings view."
            )
            section.add(OWSTableItem.disclosureItem(
                icon: .settingsPrivacy,
                name: itemTitle,
                accessibilityIdentifier: "conversation_settings_permissions",
                actionBlock: { [weak self] in
                    self?.showPermissionsSettingsView()
                }
            ))
        }

        contents.addSection(section)
    }

    private func buildMutualGroupsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(kSmallAvatarSize) + kContactCellAvatarTextMargin))

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
                    icon: .settingsAddMembers,
                    iconSize: kSmallAvatarSize,
                    innerIconSize: 24,
                    iconTintColor: Theme.primaryTextColor
                )

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("ADD_TO_GROUP_TITLE", comment: "Title of the 'add to group' view.")
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

        if mutualGroupThreads.count > 1 {
            let headerFormat = NSLocalizedString(
                "CONVERSATION_SETTINGS_MUTUAL_GROUPS_SECTION_TITLE_FORMAT",
                comment: "Format for the section title of the 'mutual groups' section in conversation settings view. Embeds: {{ the number of shared groups }}."
            )
            section.headerTitle = String(format: headerFormat, OWSFormat.formatInt(mutualGroupThreads.count))
        } else if mutualGroupThreads.count == 1 {
            section.headerTitle = NSLocalizedString(
                "CONVERSATION_SETTINGS_ONE_MUTUAL_GROUPS_SECTION_TITLE",
                comment: "Section title of the 'mutual groups' section in conversation settings view when the contact shares one mutual group."
            )
        } else {
            section.headerTitle = NSLocalizedString(
                "CONVERSATION_SETTINGS_NO_MUTUAL_GROUPS_SECTION_TITLE",
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
                actionBlock: { [weak self] in
                    self?.signalApp.presentConversation(for: groupThread, animated: true)
                }
            ))
        }

        if hasMoreGroups {
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
                        icon: .settingsShowAllMembers,
                                                                      iconSize: kSmallAvatarSize,
                                                                      innerIconSize: 24,
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
                    self?.showAllMutualGroups()
                }
            ))
        }

        return section
    }
}
