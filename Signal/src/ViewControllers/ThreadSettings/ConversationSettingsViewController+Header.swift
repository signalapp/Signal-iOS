//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// TODO: We should describe which state updates & when it is committed.
extension ConversationSettingsViewController {

    private var subtitlePointSize: CGFloat {
        UIFont.ows_dynamicTypeBody2.pointSize
    }

    private var threadName: String {
        databaseStorage.read { transaction in
            self.threadName(transaction: transaction)
        }
    }

    private func threadName(transaction: SDSAnyReadTransaction) -> String {
        var threadName = contactsManager.displayName(for: thread, transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            if let phoneNumber = contactThread.contactAddress.phoneNumber,
               phoneNumber == threadName {
                threadName = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            }
        }

        return threadName
    }

    private struct HeaderBuilder {
        let viewController: ConversationSettingsViewController
        let transaction: SDSAnyReadTransaction

        var subviews = [UIView]()

        init(viewController: ConversationSettingsViewController,
             transaction: SDSAnyReadTransaction) {

            self.viewController = viewController
            self.transaction = transaction

            addFirstSubviews()
        }

        mutating func addFirstSubviews() {
            let avatarView = buildAvatarView()

            let avatarWrapper = UIView.container()
            avatarWrapper.addSubview(avatarView)
            avatarView.autoPinEdgesToSuperviewEdges()

            if let groupThread = viewController.thread as? TSGroupThread,
                groupThread.groupModel.groupAvatarData == nil,
                viewController.canEditConversationAttributes {
                let cameraButton = GroupAttributesEditorHelper.buildCameraButtonForCorner()
                avatarWrapper.addSubview(cameraButton)
                cameraButton.autoPinEdge(toSuperviewEdge: .trailing)
                cameraButton.autoPinEdge(toSuperviewEdge: .bottom)
            }

            subviews.append(avatarWrapper)
            subviews.append(UIView.spacer(withHeight: 8))
            subviews.append(buildThreadNameLabel())
        }

        func buildAvatarView() -> UIView {
            let avatarSize: UInt = 88
            let avatarImage = OWSAvatarBuilder.buildImage(thread: viewController.thread,
                                                          diameter: avatarSize,
                                                          transaction: transaction)
            let avatarView = AvatarImageView(image: avatarImage)
            avatarView.autoSetDimensions(to: CGSize(square: CGFloat(avatarSize)))
            // Track the most recent avatar view.
            viewController.avatarView = avatarView
            return avatarView
        }

        func buildThreadNameLabel() -> UILabel {
            let label = UILabel()
            label.text = viewController.threadName(transaction: transaction)
            label.textColor = Theme.primaryTextColor
            label.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
            label.lineBreakMode = .byTruncatingTail
            return label
        }

        @discardableResult
        mutating func addSubtitleLabel(text: String, font: UIFont? = nil) -> UILabel {
            addSubtitleLabel(attributedText: NSAttributedString(string: text), font: font)
        }

        @discardableResult
        mutating func addSubtitleLabel(attributedText: NSAttributedString, font: UIFont? = nil) -> UILabel {
            subviews.append(UIView.spacer(withHeight: 8))
            let label = buildHeaderSubtitleLabel(attributedText: attributedText, font: font)
            subviews.append(label)
            return label
        }

        mutating func addLegacyGroupView(groupThread: TSGroupThread,
                                         viewController: ConversationSettingsViewController) {
            subviews.append(UIView.spacer(withHeight: 12))

            let migrationInfo = GroupsV2Migration.migrationInfoForManualMigration(groupThread: groupThread,
                                                                                  transaction: transaction)
            let legacyGroupView = LegacyGroupView(groupThread: groupThread,
                                                  migrationInfo: migrationInfo,
                                                  viewController: viewController)
            legacyGroupView.configure()
            subviews.append(legacyGroupView)
        }

        func buildHeaderSubtitleLabel(attributedText: NSAttributedString,
                                      font: UIFont?) -> UILabel {
            let label = UILabel()

            // Defaults need to be set *before* assigning the attributed text,
            // or the attributes will get overriden
            label.textColor = Theme.secondaryTextAndIconColor
            label.lineBreakMode = .byTruncatingTail
            if let font = font {
                label.font = font
            } else {
                label.font = UIFont.ows_regularFont(withSize: viewController.subtitlePointSize)
            }

            label.attributedText = attributedText

            return label
        }

        mutating func addLastSubviews() {
            // TODO Message Request: In order to debug the profile is getting shared in the right moments,
            // display the thread whitelist state in settings. Eventually we can probably delete this.
            if DebugFlags.showWhitelisted {
                let viewController = self.viewController
                let isThreadInProfileWhitelist = UIView.profileManager.isThread(inProfileWhitelist: viewController.thread,
                                                                                transaction: transaction)
                let hasSharedProfile = String(format: "Whitelisted: %@", isThreadInProfileWhitelist ? "Yes" : "No")
                addSubtitleLabel(text: hasSharedProfile)
            }
        }

        func build() -> UIView {
            let header = UIStackView(arrangedSubviews: subviews)
            header.axis = .vertical
            header.alignment = .center
            header.layoutMargins = UIEdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18)
            header.isLayoutMarginsRelativeArrangement = true

            header.addGestureRecognizer(UITapGestureRecognizer(target: viewController, action: #selector(conversationNameTouched)))

            header.isUserInteractionEnabled = true
            header.accessibilityIdentifier = UIView.accessibilityIdentifier(in: viewController, name: "mainSectionHeader")
            header.addBackgroundView(withBackgroundColor: viewController.tableBackgroundColor)

            return header
        }
    }

    private func buildHeaderForGroup(groupThread: TSGroupThread) -> UIView {
        databaseStorage.read { transaction in
            self.buildHeaderForGroup(groupThread: groupThread, transaction: transaction)
        }
    }

    private func buildHeaderForGroup(groupThread: TSGroupThread,
                                     transaction: SDSAnyReadTransaction) -> UIView {
        var builder = HeaderBuilder(viewController: self,
                                    transaction: transaction)

        if !groupThread.groupModel.isPlaceholder {
            let memberCount = groupThread.groupModel.groupMembership.fullMembers.count
            var groupMembersText = GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)
            if groupThread.isGroupV1Thread {
                groupMembersText.append(" ")
                groupMembersText.append("•")
                groupMembersText.append(" ")
                groupMembersText.append(NSLocalizedString("GROUPS_LEGACY_GROUP_INDICATOR",
                                                          comment: "Label indicating a legacy group."))
            }
            builder.addSubtitleLabel(text: groupMembersText,
                                     font: .ows_dynamicTypeSubheadline)
        }

        if groupThread.isGroupV1Thread {
            builder.addLegacyGroupView(groupThread: groupThread,
                                       viewController: self)
        }

        builder.addLastSubviews()

        let header = builder.build()

        // This will not appear in public builds.
        if DebugFlags.groupsV2showV2Indicator,
            thread.isGroupV2Thread {
            let indicatorLabel = UILabel()
            indicatorLabel.text = thread.isGroupV2Thread ? "v2" : "v1"
            indicatorLabel.textColor = Theme.secondaryTextAndIconColor
            indicatorLabel.font = .ows_dynamicTypeBody
            header.addSubview(indicatorLabel)
            indicatorLabel.autoPinEdge(toSuperviewMargin: .trailing)
            indicatorLabel.autoPinEdge(toSuperviewMargin: .bottom)
        }

        return header
    }

    private func buildHeaderForContact(contactThread: TSContactThread) -> UIView {
        databaseStorage.read { transaction in
            self.buildHeaderForContact(contactThread: contactThread, transaction: transaction)
        }
    }

    private func buildHeaderForContact(contactThread: TSContactThread,
                                       transaction: SDSAnyReadTransaction) -> UIView {
        var builder = HeaderBuilder(viewController: self,
                                    transaction: transaction)

        if !contactThread.contactAddress.isLocalAddress,
            let bioText = profileManagerImpl.profileBioForDisplay(for: contactThread.contactAddress,
                                                                  transaction: transaction) {
            let label = builder.addSubtitleLabel(text: bioText)
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .center
        }

        let threadName = contactsManager.displayName(for: contactThread, transaction: transaction)
        let recipientAddress = contactThread.contactAddress
        if let phoneNumber = recipientAddress.phoneNumber {
            let formattedPhoneNumber =
                PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            if threadName != formattedPhoneNumber {
                builder.addSubtitleLabel(text: formattedPhoneNumber)
            }
        }

        if let username = profileManagerImpl.username(for: recipientAddress, transaction: transaction),
            username.count > 0 {
            if let formattedUsername = CommonFormats.formatUsername(username),
                threadName != formattedUsername {
                builder.addSubtitleLabel(text: formattedUsername)
            }
        }

        if DebugFlags.showProfileKeyAndUuidsIndicator {
            let uuidText = String(format: "UUID: %@", contactThread.contactAddress.uuid?.uuidString ?? "Unknown")
            builder.addSubtitleLabel(text: uuidText)
        }

        let isVerified = identityManager.verificationState(for: recipientAddress,
                                                           transaction: transaction) == .verified
        if isVerified {
            let subtitle = NSMutableAttributedString()
            subtitle.appendTemplatedImage(named: "check-12", font: UIFont.ows_regularFont(withSize: builder.viewController.subtitlePointSize))
            subtitle.append(" ")
            subtitle.append(NSLocalizedString("PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                              comment: "Badge indicating that the user is verified."))
            builder.addSubtitleLabel(attributedText: subtitle)
        }

        // This will not appear in public builds.
        if DebugFlags.showProfileKeyAndUuidsIndicator {
            let profileKey = profileManager.profileKeyData(for: recipientAddress, transaction: transaction)
            let text = String(format: "Profile Key: %@", profileKey?.hexadecimalString ?? "Unknown")
            builder.addSubtitleLabel(attributedText: text.asAttributedString)
        }

        // This will not appear in public builds.
        if DebugFlags.showCapabilityIndicators {
            var capabilities = [String]()
            if GroupManager.doesUserHaveGroupsV2Capability(address: recipientAddress,
                                                           transaction: transaction) {
                capabilities.append("gv2")
            }
            if GroupManager.doesUserHaveGroupsV2MigrationCapability(address: recipientAddress,
                                                                    transaction: transaction) {
                capabilities.append("migration")
            }
            let text = String(format: "Capabilities: %@", capabilities.joined(separator: ", "))
            builder.addSubtitleLabel(attributedText: text.asAttributedString)
        }

        builder.addLastSubviews()

        return builder.build()
    }

    func buildMainHeader() -> UIView {
        if let groupThread = thread as? TSGroupThread {
            return buildHeaderForGroup(groupThread: groupThread)
        } else if let contactThread = thread as? TSContactThread {
            return buildHeaderForContact(contactThread: contactThread)
        } else {
            owsFailDebug("Invalid thread.")
            return UIView()
        }
    }
}
