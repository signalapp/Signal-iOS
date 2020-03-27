//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

extension ConversationSettingsViewController {

    // MARK: - Helpers

    private var iconSpacing: CGFloat {
        return 12
    }

    private var iconViewLength: CGFloat {
        return 24
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
        let iconView = imageView(forIcon: icon)
        let cell = buildCell(name: name, iconView: iconView)
        if let disclosureIconColor = disclosureIconColor {
            let accessoryView = OWSColorPickerAccessoryView(color: disclosureIconColor)
            accessoryView.sizeToFit()
            cell.accessoryView = accessoryView
        }
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    private func buildCell(name: String, iconView: UIView) -> UITableViewCell {
        assert(name.count > 0)

        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let rowLabel = UILabel()
        rowLabel.text = name
        rowLabel.textColor = Theme.primaryTextColor
        rowLabel.font = .ows_dynamicTypeBody
        rowLabel.lineBreakMode = .byTruncatingTail

        let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
        contentRow.spacing = self.iconSpacing

        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private func buildDisclosureCell(name: String,
                                     icon: ThemeIcon,
                                     accessibilityIdentifier: String) -> UITableViewCell {
        let cell = buildCell(name: name, icon: icon)
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    private func buildLabelCell(name: String,
                                icon: ThemeIcon,
                                accessibilityIdentifier: String) -> UITableViewCell {
        let cell = buildCell(name: name, icon: icon)
        cell.accessoryType = .none
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    private func imageView(forIcon icon: ThemeIcon) -> UIImageView {
        let iconImage = Theme.iconImage(icon)
        let iconView = UIImageView(image: iconImage)
        iconView.tintColor = Theme.primaryIconColor
        iconView.contentMode = .scaleAspectFit
        iconView.layer.minificationFilter = .trilinear
        iconView.layer.magnificationFilter = .trilinear
        iconView.autoSetDimensions(to: CGSize(width: iconViewLength, height: iconViewLength))
        return iconView
    }

    private func buildCellWithAccessoryLabel(icon: ThemeIcon,
                                             itemName: String,
                                             accessoryText: String) -> UITableViewCell {

        // We can't use the built-in UITableViewCell with CellStyle.value1,
        // because if the content of the primary label and the accessory label
        // overflow the cell layout, their contents will overlap.  We want
        // the labels to truncate in that scenario.
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let iconView = self.imageView(forIcon: icon)
        iconView.setCompressionResistanceHorizontalHigh()

        let nameLabel = UILabel()
        nameLabel.text = itemName
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.font = .ows_dynamicTypeBody
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setCompressionResistanceHorizontalLow()

        let accessoryLabel = UILabel()
        accessoryLabel.text = accessoryText
        accessoryLabel.textColor = Theme.secondaryTextAndIconColor
        accessoryLabel.font = .ows_dynamicTypeBody
        accessoryLabel.lineBreakMode = .byTruncatingTail

        let contentRow =
            UIStackView(arrangedSubviews: [ iconView, nameLabel, UIView.hStretchingSpacer(), accessoryLabel ])
        contentRow.spacing = self.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        cell.accessoryType = .disclosureIndicator

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
        let headerHeight = header.systemLayoutSizeFitting(view.frame.size).height
        mainSection.customHeaderView = header
        mainSection.customHeaderHeight = NSNumber(value: Float(headerHeight))
        mainSection.customFooterHeight = 10

        addBasicItems(to: mainSection)

        // TODO: We can remove this item once message requests are mandatory.
        addProfileSharingItems(to: mainSection)

        if shouldShowColorPicker {
            addColorPickerItems(to: mainSection)
        }

        contents.addSection(mainSection)

        if canEditConversationAttributes {
            contents.addSection(buildDisappearingMessagesSection())
        }

        if !isNoteToSelf {
            contents.addSection(buildNotificationsSection())
        }

        if let groupModel = currentGroupModel {
            if canEditConversationAccess,
                let groupModelV2 = groupModel as? TSGroupModelV2 {
                contents.addSection(buildGroupAccessSection(groupModelV2: groupModelV2))
            }
            contents.addSection(buildGroupMembershipSection(groupModel: groupModel))
        }

        if !isNoteToSelf {
            contents.addSection(buildBlockAndLeaveSection())
        }

        self.contents = contents
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
                return self.buildDisclosureCell(name: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
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
            return self.buildDisclosureCell(name: MediaStrings.allMedia,
                                            icon: .settingsAllMedia,
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "all_media"))
            },
                                 actionBlock: { [weak self] in
                                    self?.showMediaGallery()
        }))

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }
            let title = NSLocalizedString("CONVERSATION_SETTINGS_SEARCH",
                                          comment: "Table cell label in conversation settings which returns the user to the conversation with 'search mode' activated")
            return self.buildDisclosureCell(name: title,
                                            icon: .settingsSearch,
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "search"))
            },
                                 actionBlock: { [weak self] in
                                    self?.tappedConversationSearch()
        }))

        if !isNoteToSelf && !isGroupThread && thread.hasSafetyNumbers() {
            // Safety Numbers
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return self.buildDisclosureCell(name: NSLocalizedString("VERIFY_PRIVACY",
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

                return self.buildDisclosureCell(name: NSLocalizedString(
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

        let isNoteToSelf = thread.isNoteToSelf
        let isLocalUserInConversation = self.isLocalUserInConversation

        // Show profile status and allow sharing your profile for threads that are not in the whitelist.
        // This goes away when phoneNumberPrivacy is enabled, since profile sharing become mandatory.
        let (isThreadInProfileWhitelist, hasSentMessages) = databaseStorage.uiRead { transaction -> (Bool, Bool) in
            let isThreadInProfileWhitelist =
                self.profileManager.isThread(inProfileWhitelist: self.thread, transaction: transaction)
            let hasSentMessages = InteractionFinder(threadUniqueId: self.thread.uniqueId).existsOutgoingMessage(transaction: transaction)
            return (isThreadInProfileWhitelist, hasSentMessages)
        }

        let hideManualProfileSharing = (FeatureFlags.phoneNumberPrivacy
            || (RemoteConfig.messageRequests && isThreadInProfileWhitelist)
            || (RemoteConfig.messageRequests && !hasSentMessages))
        let hideProfileShareStatus = FeatureFlags.phoneNumberPrivacy || RemoteConfig.messageRequests

        if hideManualProfileSharing || isNoteToSelf {
            // Do nothing
        } else if isThreadInProfileWhitelist && !hideProfileShareStatus {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let title = (self.isGroupThread
                    ? NSLocalizedString(
                        "CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_GROUP",
                        comment: "Indicates that user's profile has been shared with a group.")
                    : NSLocalizedString(
                        "CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_USER",
                        comment: "Indicates that user's profile has been shared with a user."))
                return self.buildLabelCell(name: title,
                                           icon: .settingsProfile,
                                           accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "profile_is_shared"))
                },
                                     actionBlock: nil))
        } else {
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
                let cell = self.buildDisclosureCell(name: title,
                                                    icon: .settingsProfile,
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "share_profile"))
                cell.isUserInteractionEnabled = isLocalUserInConversation
                return cell
                },
                                     actionBlock: { [weak self] in
                                        self?.showShareProfileAlert()
            }))
        }
    }

    private func buildDisappearingMessagesSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 10

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
            let iconView = self.imageView(forIcon: icon)

            let rowLabel = UILabel()
            rowLabel.text = NSLocalizedString(
                "DISAPPEARING_MESSAGES", comment: "table cell label in conversation settings")
            rowLabel.textColor = Theme.primaryTextColor
            rowLabel.font = .ows_dynamicTypeBody
            rowLabel.lineBreakMode = .byTruncatingTail

            let switchView = UISwitch()
            switchView.isOn = disappearingMessagesConfiguration.isEnabled
            switchView.addTarget(self, action: switchAction, for: .valueChanged)

            let topRow = UIStackView(arrangedSubviews: [ iconView, rowLabel, switchView ])
            topRow.spacing = self.iconSpacing
            topRow.alignment = .center
            cell.contentView.addSubview(topRow)
            topRow.autoPinEdgesToSuperviewMargins()

            switchView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_switch")
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")

            return cell
            },
                                 customRowHeight: UITableView.automaticDimension,
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

                let iconView = self.imageView(forIcon: .settingsTimer)
                let rowLabel = self.disappearingMessagesDurationLabel
                self.updateDisappearingMessagesDurationLabel()
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = .ows_dynamicTypeBody
                // don't truncate useful duration info which is in the tail
                rowLabel.lineBreakMode = .byTruncatingHead

                let topRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                topRow.spacing = self.iconSpacing
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

                slider.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_slider")
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_duration")

                return cell
                },
                                     customRowHeight: UITableView.automaticDimension,
                                     actionBlock: nil))
        }

        section.footerTitle = NSLocalizedString(
            "DISAPPEARING_MESSAGES_DESCRIPTION", comment: "subheading in conversation settings")

        return section
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
        section.customHeaderHeight = 10
        section.customFooterHeight = 10

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let sound = OWSSounds.notificationSound(for: self.thread)
            let cell = self.buildCellWithAccessoryLabel(icon: .settingsMessageSound,
                                                        itemName: NSLocalizedString("SETTINGS_ITEM_NOTIFICATION_SOUND",
                                                                                    comment: "Label for settings view that allows user to change the notification sound."),
                                                        accessoryText: OWSSounds.displayName(for: sound))
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "notifications")
            return cell
            },
                                 customRowHeight: UITableView.automaticDimension,
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

            let cell = self.buildCellWithAccessoryLabel(icon: .settingsMuted,
                                                        itemName: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_LABEL",
                                                                                    comment: "label for 'mute thread' cell in conversation settings"),
                                                        accessoryText: muteStatus)

            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mute")

            return cell
            },
                                 customRowHeight: UITableView.automaticDimension,
                                 actionBlock: { [weak self] in
                                    self?.showMuteUnmuteActionSheet()
        }))

        return section
    }

    private func buildBlockAndLeaveSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 10
        section.customFooterHeight = 10

        let switchAction = #selector(blockConversationSwitchDidChange)
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let cellTitle =
                (self.thread.isGroupThread
                    ? NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_THIS_GROUP",
                                        comment: "table cell label in conversation settings")
                    : NSLocalizedString("CONVERSATION_SETTINGS_BLOCK_THIS_USER",
                                        comment: "table cell label in conversation settings"))
            let cell = self.buildDisclosureCell(name: cellTitle,
                                                icon: .settingsBlock,
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "block"))

            cell.selectionStyle = .none

            let switchView = UISwitch()
            switchView.isOn = self.blockingManager.isThreadBlocked(self.thread)
            switchView.addTarget(self, action: switchAction, for: .valueChanged)
            cell.accessoryView = switchView
            switchView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "block_conversation_switch")

            return cell
            },
                                 actionBlock: nil))

        if isGroupThread, isLocalUserInConversation {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let cell = self.buildCell(name: NSLocalizedString("LEAVE_GROUP_ACTION",
                                                                  comment: "table cell label in conversation settings"),
                                          icon: .settingsLeaveGroup,
                                          accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group"))
                return cell
                },
                                     actionBlock: { [weak self] in
                                        self?.didTapLeaveGroup()
            }))
        }

        return section
    }

    private func buildGroupAccessSection(groupModelV2: TSGroupModelV2) -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 10
        section.customFooterHeight = 10

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }

            let accessStatus: String
            switch groupModelV2.access.attributes {
            case .unknown, .any, .member:
                if groupModelV2.access.attributes != .member {
                    owsFailDebug("Invalid attributes access: \(groupModelV2.access.attributes.rawValue)")
                }
                accessStatus = NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_MEMBER",
                                                 comment: "Label indicating that all group members can update the group's attributes: name, avatar, etc.")
            case .administrator:
                accessStatus = NSLocalizedString("CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_ADMINISTRATOR",
                                                 comment: "Label indicating that only administrators can update the group's attributes: name, avatar, etc.")
            }
            let cell = self.buildCellWithAccessoryLabel(icon: .settingsEditGroupAccess,
                                                        itemName: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS",
                                                                                    comment: "Label for 'edit attributes access' action in conversation settings view."),
                                                        accessoryText: accessStatus)
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "edit_group_access")
            return cell
            },
                                 actionBlock: { [weak self] in
                                    self?.showGroupAttributesAccessView()
        }))

        return section
    }

    private func buildGroupMembershipSection(groupModel: TSGroupModel) -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 10
        section.customFooterHeight = 10

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return section
        }
        guard let helper = self.contactsViewHelper else {
            owsFailDebug("Missing contactsViewHelper.")
            return section
        }

        // "Add Members" cell.
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true

            let iconView = self.imageView(forIcon: .settingsAddMembers)
            iconView.tintColor = .ows_accentBlue

            let rowLabel = UILabel()
            rowLabel.text = NSLocalizedString("CONVERSATION_SETTINGS_ADD_MEMBERS",
                                              comment: "Label for 'add members' button in conversation settings view.")
            rowLabel.textColor = .ows_accentBlue
            rowLabel.font = .ows_dynamicTypeBody
            rowLabel.lineBreakMode = .byTruncatingTail

            let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
            contentRow.spacing = self.iconSpacing

            cell.contentView.addSubview(contentRow)
            contentRow.autoPinEdgesToSuperviewMargins()

            return cell
            },
                                 customRowHeight: UITableView.automaticDimension) { [weak self] in
                                    self?.showAddMembersView()
        })

        let groupMembership = groupModel.groupMembership
        let allMembers = groupMembership.nonPendingMembers

        var verificationStateMap = [SignalServiceAddress: OWSVerificationState]()
        var comparableNameMap = [SignalServiceAddress: String]()
        databaseStorage.uiRead { transaction in
            for memberAddress in allMembers {
                verificationStateMap[memberAddress] = self.identityManager.verificationState(for: memberAddress,
                                                                                             transaction: transaction)
                comparableNameMap[memberAddress] = self.contactsManager.comparableName(for: memberAddress,
                                                                                       transaction: transaction)
            }
        }

        // Sort member blocks using comparable names.
        let sortAddressSet = { (addressSet: Set<SignalServiceAddress>) -> [SignalServiceAddress] in
            return Array(addressSet).sorted { (left, right) -> Bool in
                guard let leftName = comparableNameMap[left] else {
                    owsFailDebug("Missing comparableName")
                    return false
                }
                guard let rightName = comparableNameMap[right] else {
                    owsFailDebug("Missing comparableName")
                    return false
                }
                return leftName < rightName
            }
        }
        var sortedMembers = [SignalServiceAddress]()
        if groupMembership.isNonPendingMember(localAddress) {
            // Make sure local user is first.
            sortedMembers.insert(localAddress, at: 0)
        }
        // Admin users are second.
        let adminMembers = allMembers.filter { $0 != localAddress && groupMembership.isAdministrator($0) }
        sortedMembers += sortAddressSet(adminMembers)
        // Non-admin users are third.
        let nonAdminMembers = allMembers.filter { $0 != localAddress && !groupMembership.isAdministrator($0) }
        sortedMembers += sortAddressSet(nonAdminMembers)

        // TODO: Do we show pending members here? How?
        var hasMoreMembers = groupMembership.pendingMembers.count > 0
        for memberAddress in sortedMembers {
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

            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                let cell = ContactTableViewCell()
                let isLocalUser = memberAddress == localAddress
                let isGroupAdmin = groupMembership.isAdministrator(memberAddress)
                let isVerified = verificationState == .verified
                let isNoLongerVerified = verificationState == .noLongerVerified
                let isBlocked = helper.isSignalServiceAddressBlocked(memberAddress)
                if isNoLongerVerified {
                    cell.setAccessoryMessage(NSLocalizedString("CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                                                               comment: "An indicator that a contact is no longer verified."))
                } else if isBlocked {
                    cell.setAccessoryMessage(MessageStrings.conversationIsBlocked)
                }

                cell.configure(withRecipientAddress: memberAddress)

                if isLocalUser {
                    cell.setCustomName(self.contactsManager.displayName(for: memberAddress) +
                    " " +
                        NSLocalizedString("GROUP_MEMBER_LOCAL_USER_INDICATOR",
                                          comment: "Label indicating the local user."))
                }

                if isGroupAdmin {
                    let subtitle = NSAttributedString(string: NSLocalizedString("GROUP_MEMBER_ADMIN_INDICATOR",
                                                                                comment: "Label indicating that a group member is an admin."),
                                                      attributes: [
                                                        .font: UIFont.ows_dynamicTypeBody.ows_semibold(),
                                                        .foregroundColor: Theme.primaryTextColor
                    ])
                    cell.setAttributedSubtitle(subtitle)
                } else if isVerified {
                    cell.setAttributedSubtitle(cell.verifiedSubtitle())
                } else {
                    cell.setAttributedSubtitle(nil)
                }

                let cellName = "user.\(memberAddress.stringForDisplay)"
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: cellName)

                return cell
                },
                                     customRowHeight: UITableView.automaticDimension) { [weak self] in
                                        self?.didSelectGroupMember(memberAddress)
            })
        }

        if hasMoreMembers {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }
                return self.buildCell(name: NSLocalizedString("CONVERSATION_SETTINGS_VIEW_ALL_MEMBERS",
                                                              comment: "Label for 'view all members' button in conversation settings view."),
                                      icon: .settingsShowAllMembers)
                },
                                     customRowHeight: UITableView.automaticDimension) { [weak self] in
                                        self?.showAllGroupMembers()
            })
        }

        return section
    }
}
