//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        return contactsManager.hasSignalAccount(for: contactThread.contactAddress)
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
        contents.title = NSLocalizedString("CONVERSATION_SETTINGS", comment: "title for conversation settings screen")

        let isNoteToSelf = thread.isNoteToSelf

        // Main section.
        let mainSection = OWSTableSection()
        let header = buildMainHeader()
        lastContentWidth = view.width
        mainSection.customHeaderView = header
        addBasicItems(to: mainSection)

        // TODO: We can remove this item once message requests are mandatory.
        addProfileSharingItems(to: mainSection)

        if DebugFlags.shouldShowColorPicker {
            addColorPickerItems(to: mainSection)
        }

        contents.addSection(mainSection)

        buildDisappearingMessagesSection(to: mainSection)

        if !isNoteToSelf {
            contents.addSection(buildNotificationsSection())
        }

        if let groupModel = currentGroupModel,
            !groupModel.isPlaceholder {
            if let groupModelV2 = groupModel as? TSGroupModelV2 {
                if canEditConversationAccess {
                    buildGroupAccessSections(groupModelV2: groupModelV2, contents: contents)
                }

                buildRequestsInvitesAndLinkSection(groupModelV2: groupModelV2, contents: contents)
            }

            contents.addSection(buildGroupMembershipSection(groupModel: groupModel))
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

    private func addBasicItems(to section: OWSTableSection) {

        let isNoteToSelf = thread.isNoteToSelf

        if let contactThread = thread as? TSContactThread,
            contactsManager.supportsContactEditing && !hasExistingContact {
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

        if !isNoteToSelf && !isGroupThread && thread.hasSafetyNumbers() {
            // Safety Numbers
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
                                        if self.contactsManager.supportsContactEditing {
                                            self.presentContactViewController()
                                        }
            }))
        }
    }

    private func addProfileSharingItems(to section: OWSTableSection) {
        guard !thread.isGroupV2Thread else {
            return
        }

        let isLocalUserFullMember = self.isLocalUserFullMember

        // For pre-message request threads, allow manually sharing your profile if the thread is not whitelisted.
        let (isPreMessageRequestsThread, isThreadInProfileWhitelist) = databaseStorage.uiRead { transaction -> (Bool, Bool) in
            return (
                GRDBThreadFinder.isPreMessageRequestsThread(self.thread, transaction: transaction.unwrapGrdbRead),
                Self.profileManager.isThread(inProfileWhitelist: self.thread, transaction: transaction)
            )
        }

        if isPreMessageRequestsThread && !isThreadInProfileWhitelist {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let title =
                    (self.isGroupThread
                        ? NSLocalizedString("CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_GROUP",
                                            comment: "Action that shares user profile with a group.")
                        : NSLocalizedString("CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_USER",
                                            comment: "Action that shares user profile with a user."))
                let cell = OWSTableItem.buildDisclosureCell(name: title,
                                                            icon: .settingsProfile,
                                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "share_profile"))
                cell.isUserInteractionEnabled = isLocalUserFullMember
                return cell
                },
                                     actionBlock: { [weak self] in
                                        self?.showShareProfileAlert()
            }))
        }
    }

    private func buildDisappearingMessagesSection(to section: OWSTableSection) {

        let canEditConversationAttributes = self.canEditConversationAttributes

        let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration = self.disappearingMessagesConfiguration
        let switchAction = #selector(disappearingMessagesSwitchValueDidChange)
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true
            cell.selectionStyle = .none

            let icon: ThemeIcon = (disappearingMessagesConfiguration.isEnabled
                ? .settingsTimer
                : .settingsTimerDisabled)
            let iconView = OWSTableItem.imageView(forIcon: icon)

            let rowLabel = UILabel()
            rowLabel.text = NSLocalizedString(
                "DISAPPEARING_MESSAGES", comment: "table cell label in conversation settings")
            rowLabel.textColor = Theme.primaryTextColor
            rowLabel.font = OWSTableItem.primaryLabelFont
            rowLabel.lineBreakMode = .byTruncatingTail

            let switchView = UISwitch()
            switchView.isOn = disappearingMessagesConfiguration.isEnabled
            switchView.addTarget(self, action: switchAction, for: .valueChanged)
            switchView.isEnabled = canEditConversationAttributes

            let topRow = UIStackView(arrangedSubviews: [ iconView, rowLabel, switchView ])
            topRow.spacing = self.iconSpacingLarge
            topRow.alignment = .center
            cell.contentView.addSubview(topRow)
            topRow.autoPinEdgesToSuperviewMargins()

            switchView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_switch")
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")

            return cell
            },
                                 actionBlock: nil))

        if disappearingMessagesConfiguration.isEnabled {
            let sliderAction = #selector(durationSliderDidChange)
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.selectionStyle = .none

                let iconView = OWSTableItem.imageView(forIcon: .settingsTimer)
                let rowLabel = self.disappearingMessagesDurationLabel
                self.updateDisappearingMessagesDurationLabel()
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                // don't truncate useful duration info which is in the tail
                rowLabel.lineBreakMode = .byTruncatingTail

                let topRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                topRow.spacing = self.iconSpacingLarge
                topRow.alignment = .center
                cell.contentView.addSubview(topRow)
                topRow.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

                let slider = UISlider()
                slider.maximumValue
                    = Float(self.disappearingMessagesDurations.count - 1)
                slider.minimumValue = 0
                slider.isContinuous = true // NO fires change event only once you let go
                slider.value = Float(self.disappearingMessagesConfiguration.durationIndex)
                slider.addTarget(self, action: sliderAction, for: .valueChanged)
                cell.contentView.addSubview(slider)
                slider.autoPinEdge(.top, to: .bottom, of: topRow, withOffset: 6)
                slider.autoPinEdge(.leading, to: .leading, of: rowLabel)
                slider.autoPinTrailingToSuperviewMargin()
                slider.autoPinBottomToSuperviewMargin()
                slider.isEnabled = canEditConversationAttributes

                slider.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_slider")
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_duration")

                return cell
                },
                                     actionBlock: nil))
        }

        section.footerTitle = NSLocalizedString(
            "DISAPPEARING_MESSAGES_DESCRIPTION", comment: "subheading in conversation settings")
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

    private func buildNotificationsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 14
        section.customFooterHeight = 14

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let sound = OWSSounds.notificationSound(for: self.thread)
            let cell = OWSTableItem.buildCellWithAccessoryLabel(icon: .settingsMessageSound,
                                                                itemName: NSLocalizedString("SETTINGS_ITEM_NOTIFICATION_SOUND",
                                                                                            comment: "Label for settings view that allows user to change the notification sound."),
                                                                accessoryText: OWSSounds.displayName(forSound: sound))
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "notifications")
            return cell
            },
                                 actionBlock: { [weak self] in
                                    self?.showSoundSettingsView()
        }))

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            var muteStatus = NSLocalizedString("CONVERSATION_SETTINGS_MUTE_NOT_MUTED",
                                               comment: "Indicates that the current thread is not muted.")

            let now = Date()
            if let mutedUntilDate = self.thread.mutedUntilDate,
                mutedUntilDate > now {
                let calendar = Calendar.current
                let muteUntilComponents = calendar.dateComponents([.year, .month, .day], from: mutedUntilDate)
                let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
                let dateFormatter = DateFormatter()
                if nowComponents.year != muteUntilComponents.year
                    || nowComponents.month != muteUntilComponents.month
                    || nowComponents.day != muteUntilComponents.day {

                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                } else {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .short
                }

                let formatString = NSLocalizedString("CONVERSATION_SETTINGS_MUTED_UNTIL_FORMAT",
                                                     comment: "Indicates that this thread is muted until a given date or time. Embeds {{The date or time which the thread is muted until}}.")
                muteStatus = String(format: formatString,
                                    dateFormatter.string(from: mutedUntilDate))
            }

            let cell = OWSTableItem.buildCellWithAccessoryLabel(icon: .settingsMuted,
                                                                itemName: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_LABEL",
                                                                                            comment: "label for 'mute thread' cell in conversation settings"),
                                                                accessoryText: muteStatus)

            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mute")

            return cell
            },
                                 actionBlock: { [weak self] in
                                    self?.showMuteUnmuteActionSheet()
        }))

        if Mention.threadAllowsMentionSend(thread) {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let cell = OWSTableItem.buildCellWithAccessoryLabel(icon: .settingsMention,
                                                                    itemName: NSLocalizedString("CONVERSATION_SETTINGS_MENTIONS_LABEL",
                                                                                                comment: "label for 'mentions' cell in conversation settings"),
                                                                    accessoryText: self.nameForMentionMode(self.thread.mentionNotificationMode))

                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mentions")

                return cell
                },
                                     actionBlock: { [weak self] in
                                        self?.showMentionNotificationModeActionSheet()
            }))
        }

        return section
    }

    func nameForMentionMode(_ mode: TSThreadMentionNotificationMode) -> String {
        switch mode {
        case .default, .always:
            return NSLocalizedString("CONVERSATION_SETTINGS_MENTION_MODE_AlWAYS",
                                     comment: "label for 'always' option for mention notifications in conversation settings")
        case .never:
            return NSLocalizedString("CONVERSATION_SETTINGS_MENTION_MODE_NEVER",
                                     comment: "label for 'never' option for mention notifications in conversation settings")
        }
    }

    private func buildBlockAndLeaveSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 14

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

    private func buildGroupAccessSections(groupModelV2: TSGroupModelV2,
                                          contents: OWSTableContents) {

        let section = OWSTableSection()
        section.customHeaderHeight = 14

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let accessStatus = self.accessoryLabel(forAccess: groupModelV2.access.members)
            let cell = OWSTableItem.buildCellWithAccessoryLabel(icon: .settingsEditGroupAccess,
                                                                itemName: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS",
                                                                                            comment: "Label for 'edit membership access' action in conversation settings view."),
                                                                accessoryText: accessStatus)
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "edit_group_membership_access")
            return cell
            },
                                 actionBlock: { [weak self] in
                                    self?.showGroupMembershipAccessView()
        }))

        section.footerTitle = NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_SECTION_FOOTER",
                                                comment: "Footer for the 'attributes access' section in conversation settings view.")

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let accessStatus = self.accessoryLabel(forAccess: groupModelV2.access.attributes)
            let cell = OWSTableItem.buildCellWithAccessoryLabel(icon: .settingsEditGroupAccess,
                                                                itemName: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS",
                                                                                            comment: "Label for 'edit attributes access' action in conversation settings view."),
                                                                accessoryText: accessStatus)
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "edit_group_attributes_access")
            return cell
            },
                                 actionBlock: { [weak self] in
                                    self?.showGroupAttributesAccessView()
        }))
        contents.addSection(section)
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
        section.customFooterHeight = 14

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
                                                                  innerIconSize: 22)

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("CONVERSATION_SETTINGS_ADD_MEMBERS",
                                                  comment: "Label for 'add members' button in conversation settings view.")
                rowLabel.textColor = Theme.accentBlueColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacingSmall

                cell.contentView.addSubview(contentRow)
                contentRow.autoPinEdgesToSuperviewMargins()

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
            allMembersSorted = self.contactsManager.sortSignalServiceAddresses(Array(allMembers),
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

        // TODO: Do we show pending members here? How?
        var hasMoreMembers = false
        for memberAddress in membersToRender {
            let maxMembersToShow = 5
            // Note that we use <= to account for the header cell.
            guard isShowingAllGroupMembers || section.itemCount() <= maxMembersToShow else {
                hasMoreMembers = true
                break
            }

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
                cell.setUseSmallAvatars()

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
                    let customAvatar = OWSProfileManager.shared().localProfileAvatarImage() ?? OWSContactAvatarBuilder(forLocalUserWithDiameter: kSmallAvatarSize).buildDefaultImage()
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
                                                                  innerIconSize: 19,
                                                                  iconTintColor: Theme.secondaryTextAndIconColor)

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("CONVERSATION_SETTINGS_VIEW_ALL_MEMBERS",
                                                  comment: "Label for 'view all members' button in conversation settings view.")
                rowLabel.textColor = Theme.secondaryTextAndIconColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacingSmall

                cell.contentView.addSubview(contentRow)
                contentRow.autoPinEdgesToSuperviewMargins()

                return cell
                }) { [weak self] in
                                        self?.showAllGroupMembers()
            })
        }

        return section
    }

    private func buildRequestsInvitesAndLinkSection(groupModelV2: TSGroupModelV2,
                                                    contents: OWSTableContents) {

        let section = OWSTableSection()
        section.customHeaderHeight = 14
        section.customFooterHeight = 14

        let itemTitle = (RemoteConfig.groupsV2InviteLinks
            ? NSLocalizedString("CONVERSATION_SETTINGS_MEMBER_REQUESTS_AND_INVITES",
                                comment: "Label for 'member requests & invites' action in conversation settings view.")
            : NSLocalizedString("CONVERSATION_SETTINGS_MEMBER_INVITES",
                                comment: "Label for 'member invites' action in conversation settings view."))
        section.add(OWSTableItem.disclosureItem(icon: .settingsViewRequestAndInvites,
                                                name: itemTitle,
                                                accessibilityIdentifier: "conversation_settings_requests_and_invites",
                                                actionBlock: { [weak self] in
                                                    self?.showMemberRequestsAndInvitesView()
        }))

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

        contents.addSection(section)
    }
}
