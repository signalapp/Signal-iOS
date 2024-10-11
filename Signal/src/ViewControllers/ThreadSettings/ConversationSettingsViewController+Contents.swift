//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
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

    // MARK: - Table

    func updateTableContents(shouldReload: Bool = true) {

        let contents = OWSTableContents()

        let isNoteToSelf = thread.isNoteToSelf

        let callDetailsSection = createCallSection()
        if let callDetailsSection {
            contents.add(callDetailsSection)
        }

        let mainSection = OWSTableSection()

        let firstSection = callDetailsSection ?? mainSection

        let header = buildMainHeader()
        lastContentWidth = view.width
        firstSection.customHeaderView = header

        // Main section.
        addDisappearingMessagesItem(to: mainSection)
        addNicknameItemIfNecessary(to: mainSection)
        addColorAndWallpaperSettingsItem(to: mainSection)
        if !isNoteToSelf { addSoundAndNotificationSettingsItem(to: mainSection) }
        addSafetyNumberItemIfNecessary(to: mainSection)

        contents.add(mainSection)

        // Middle sections
        addSystemContactSectionIfNecessary(to: contents)
        addAllMediaSectionIfNecessary(to: contents)
        addBadgesItemIfNecessary(to: contents)

        // Group sections
        if let groupModel = currentGroupModel, !groupModel.isPlaceholder {
            contents.add(buildGroupMembershipSection(groupModel: groupModel, sectionIndex: contents.sections.count))

            if let groupModelV2 = groupModel as? TSGroupModelV2 {
                buildGroupSettingsSection(groupModelV2: groupModelV2, contents: contents)
            }
        } else if isContactThread, hasGroupThreads, !isNoteToSelf {
            contents.add(buildMutualGroupsSection(sectionIndex: contents.sections.count))
        }

        // Bottom sections
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
    }

    // MARK: Calls section

    private func createCallSection() -> OWSTableSection? {
        return Self.createCallHistorySection(callRecords: callRecords)
    }

    static func createCallHistorySection(callRecords: [CallRecord]) -> OWSTableSection? {
        guard let callRecord = callRecords.first else {
            return nil
        }

        let section = OWSTableSection()

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8

        let dateLabel = UILabel()
        dateLabel.font = .dynamicTypeBody
        dateLabel.textColor = Theme.primaryTextColor
        // We always want to show the absolute date with year
        dateLabel.text = DateUtil.formatOldDate(callRecord.callBeganDate)
        stackView.addArrangedSubview(dateLabel)
        stackView.setCustomSpacing(10, after: dateLabel)

        typealias CallRow = (icon: ThemeIcon, description: String, timestamp: String)
        let callRows: [CallRow] = callRecords.map { callRecord in
            let icon: ThemeIcon = {
                switch callRecord.callType {
                case .audioCall:
                    return .phone16
                case .adHocCall, .groupCall, .videoCall:
                    return .video16
                }
            }()

            let description: String = {
                enum CallMedium {
                    case audioCall
                    case videoCall
                }
                let callMedium: CallMedium
                switch callRecord.callType {
                case .adHocCall:
                    return CallStrings.callLink
                case .audioCall:
                    callMedium = .audioCall
                case .groupCall, .videoCall:
                    callMedium = .videoCall
                }
                if callRecord.callStatus.isMissedCall {
                    switch callMedium {
                    case .audioCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_MISSED_VOICE_CALL",
                            comment: "A label indicating that a call was an missed voice call"
                        )
                    case .videoCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_MISSED_VIDEO_CALL",
                            comment: "A label indicating that a call was an missed video call"
                        )
                    }
                }
                switch callRecord.callDirection {
                case .outgoing:
                    switch callMedium {
                    case .audioCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_OUTGOING_VOICE_CALL",
                            comment: "A label indicating that a call was an outgoing voice call"
                        )
                    case .videoCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_OUTGOING_VIDEO_CALL",
                            comment: "A label indicating that a call was an outgoing video call"
                        )
                    }
                case .incoming:
                    switch callMedium {
                    case .audioCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_INCOMING_VOICE_CALL",
                            comment: "A label indicating that a call was an incoming voice call"
                        )
                    case .videoCall:
                        return OWSLocalizedString(
                            "CONVERSATION_SETTINGS_CALL_DETAILS_INCOMING_VIDEO_CALL",
                            comment: "A label indicating that a call was an incoming video call"
                        )
                    }
                }
            }()

            let timestamp = DateUtil.formatDateAsTime(callRecord.callBeganDate)
            return (icon, description, timestamp)
        }

        for callRow in callRows {
            stackView.addArrangedSubview({
                let hStack = UIStackView()
                hStack.axis = .horizontal
                hStack.spacing = 6
                hStack.addArrangedSubview(UIImageView.withTemplateIcon(
                    callRow.icon,
                    tintColor: Theme.primaryTextColor,
                    constrainedTo: .square(16)
                ))
                hStack.tintColor = Theme.primaryTextColor

                let descriptionLabel = UILabel()
                descriptionLabel.font = .dynamicTypeSubheadline
                descriptionLabel.textColor = Theme.primaryTextColor
                descriptionLabel.text = callRow.description
                hStack.addArrangedSubview(descriptionLabel)

                hStack.addArrangedSubview(UIView.hStretchingSpacer())

                let timestampLabel = UILabel()
                timestampLabel.font = .dynamicTypeSubheadline
                timestampLabel.textColor = Theme.secondaryTextAndIconColor
                timestampLabel.text = callRow.timestamp
                hStack.addArrangedSubview(timestampLabel)

                return hStack
            }())
        }

        section.add(.init(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()
            return cell
        }))

        return section
    }

    // MARK: Middle sections

    private func addAllMediaSectionIfNecessary(to contents: OWSTableContents) {
        guard !recentMedia.isEmpty else { return }

        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_ALL_MEDIA_HEADER",
            comment: "Header title for the section showing all media in conversation settings"
        )

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

        let (visibleBadges, shortName) = SSKEnvironment.shared.databaseStorageRef.read { tx -> ([OWSUserProfileBadgeInfo], String) in
            let visibleBadges: [OWSUserProfileBadgeInfo] = {
                let tsAccountManager = DependenciesBridge.shared.tsAccountManager
                guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                    return []
                }
                let address = OWSUserProfile.internalAddress(for: contactAddress, localIdentifiers: localIdentifiers)
                guard let userProfile = OWSUserProfile.getUserProfile(for: address, tx: tx) else {
                    return []
                }
                return userProfile.visibleBadges
            }()
            let shortName = SSKEnvironment.shared.contactManagerRef.displayName(for: contactAddress, tx: tx).resolvedValue(useShortNameIfAvailable: true)
            return (visibleBadges, shortName)
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

    // MARK: Main section

    private func addSafetyNumberItemIfNecessary(to section: OWSTableSection) {
        guard !thread.isNoteToSelf, !isGroupThread, thread.hasSafetyNumbers() else { return }

        section.add(
            OWSTableItem.disclosureItem(
                icon: .contactInfoSafetyNumber,
                withText: OWSLocalizedString(
                    "VERIFY_PRIVACY",
                    comment: "Label for button or row which allows users to verify the safety number of another user."
                ),
                actionBlock: { [weak self] in
                    self?.showVerificationView()
                }
            )
        )
    }

    private func addSystemContactSectionIfNecessary(to contents: OWSTableContents) {
        guard !thread.isNoteToSelf, let contactThread = thread as? TSContactThread else { return }

        let section = OWSTableSection()

        if isSystemContact {
            section.add(
                OWSTableItem.disclosureItem(
                    icon: .contactInfoUserInContacts,
                    withText: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                        comment: "Indicates that user is in the system contacts list."
                    ),
                    actionBlock: { [weak self] in
                        self?.presentCreateOrEditContactViewController(
                            address: contactThread.contactAddress,
                            editImmediately: false
                        )
                    }
                )
            )
        } else if contactThread.contactAddress.phoneNumber != nil {
            section.add(
                OWSTableItem.disclosureItem(
                    icon: .contactInfoAddToContacts,
                    withText: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                        comment: "button in conversation settings view."
                    ),
                    actionBlock: { [weak self] in
                        self?.showAddToSystemContactsActionSheet(contactThread: contactThread)
                    }
                )
            )
        }

        contents.add(section)
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

    private func addNicknameItemIfNecessary(to section: OWSTableSection) {
        guard
            !self.thread.isNoteToSelf,
            let thread = self.thread as? TSContactThread
        else { return }
        section.add(.item(
            icon: .buttonEdit,
            name: OWSLocalizedString(
                "NICKNAME_BUTTON_TITLE",
                comment: "Title for the table cell in conversation settings for presenting the profile nickname editor."
            ),
            accessoryType: .disclosureIndicator,
            actionBlock: { [weak self] in
                guard let self else { return }
                let db = DependenciesBridge.shared.db

                let nicknameEditor = db.read { tx in
                    NicknameEditorViewController.create(
                        for: thread.contactAddress,
                        context: .init(
                            db: db,
                            nicknameManager: DependenciesBridge.shared.nicknameManager
                        ),
                        tx: tx
                    )
                }
                guard let nicknameEditor else { return }
                let navigationController = OWSNavigationController(rootViewController: nicknameEditor)
                self.presentFormSheet(navigationController, animated: true)
            }))
    }

    // MARK: Bottom sections

    private func buildBlockAndLeaveSection() -> OWSTableSection {
        let section = OWSTableSection()

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

        let hasReportedSpam = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return InteractionFinder(threadUniqueId: thread.uniqueId).hasUserReportedSpam(transaction: tx)
        }

        if !hasReportedSpam {
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                return OWSTableItem.buildCell(
                    icon: .spam,
                    itemName: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_REPORT_SPAM",
                        comment: "Label for 'report spam' action in conversation settings view."
                    ),
                    customColor: UIColor.ows_accentRed,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "report_spam")
                )
            },
            actionBlock: { [weak self] in
                self?.didTapReportSpam()
            }))
        }

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

    // MARK: Group sections

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

                SSKEnvironment.shared.databaseStorageRef.read { transaction in
                    let configuration = ContactCellConfiguration(address: memberAddress, localUserDisplayMode: .asLocalUser)
                    let isGroupAdmin = groupMembership.isFullMemberAndAdministrator(memberAddress)
                    let isVerified = verificationState == .verified
                    let isNoLongerVerified = verificationState == .noLongerVerified
                    let isBlocked = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(memberAddress, transaction: transaction)
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
                              let bioForDisplay = (SSKEnvironment.shared.profileManagerImplRef.profileBioForDisplay(for: memberAddress,
                                                                                                transaction: transaction)) {
                        configuration.attributedSubtitle = NSAttributedString(string: bioForDisplay)
                    } else {
                        owsAssertDebug(configuration.attributedSubtitle == nil)
                    }

                    let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: memberAddress, transaction: transaction) != nil
                    configuration.shouldShowContactIcon = isSystemContact

                    cell.configure(configuration: configuration, transaction: transaction)
                }

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
            withText: OWSLocalizedString(
                "CONVERSATION_SETTINGS_GROUP_LINK",
                comment: "Label for 'group link' action in conversation settings view."
            ),
            accessoryText: groupLinkStatus,
            actionBlock: { [weak self] in
                self?.showGroupLinkView()
            })
        )

        let itemTitle = OWSLocalizedString("CONVERSATION_SETTINGS_MEMBER_REQUESTS_AND_INVITES",
                                          comment: "Label for 'member requests & invites' action in conversation settings view.")
        section.add(OWSTableItem.disclosureItem(
            icon: .groupInfoRequestAndInvites,
            withText: itemTitle,
            accessoryText: OWSFormat.formatInt(groupModelV2.groupMembership.invitedOrRequestMembers.count),
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
                withText: itemTitle,
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
