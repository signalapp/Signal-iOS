//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit
import ContactsUI

@objc
class ConversationSettingsViewController: OWSTableViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var blockingManager: OWSBlockingManager {
        return .shared()
    }

    private var profileManager: OWSProfileManager {
        return .shared()
    }

    private var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    // MARK: -

    @objc
    public weak var conversationSettingsViewDelegate: OWSConversationSettingsViewDelegate?

    private let threadViewModel: ThreadViewModel

    private var thread: TSThread {
        return threadViewModel.threadRecord
    }

    public var showVerificationOnAppear = false

    private var contactsViewHelper: ContactsViewHelper?

    private var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration!
    private var avatarView: UIImageView?
    private let disappearingMessagesDurationLabel = UILabel()

    // This is currently disabled behind a feature flag.
    private var colorPicker: ColorPicker?

    private let kIconViewLength: CGFloat = 24

    @objc
    public required init(threadViewModel: ThreadViewModel) {
        self.threadViewModel = threadViewModel

        super.init()

        contactsViewHelper = ContactsViewHelper(delegate: self)
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(identityStateDidChange(notification:)),
                                               name: .identityStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange(notification:)),
                                               name: .profileWhitelistDidChange,
                                               object: nil)
    }

    // MARK: - Accessors

    private var threadName: String {
        var threadName = contactsManager.displayNameWithSneakyTransaction(thread: thread)

        if let contactThread = thread as? TSContactThread {
            if let phoneNumber = contactThread.contactAddress.phoneNumber,
                phoneNumber == threadName {
                threadName = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            }
        }

        return threadName
    }

    private var canEditSharedConversationSettings: Bool {
        if threadViewModel.hasPendingMessageRequest {
            return false
        }

        return isLocalUserInConversation
    }

    private var isLocalUserInConversation: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return true
        }

        return groupThread.isLocalUserInGroup
    }

    private var isGroupThread: Bool {
        return thread.isGroupThread
    }

    private var isContactThread: Bool {
        return !thread.isGroupThread
    }

    private var hasSavedGroupIcon: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        guard let groupAvatarData = groupThread.groupModel.groupAvatarData else {
            return false
        }
        return groupAvatarData.count > 0
    }

    private var hasExistingContact: Bool {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return false
        }
        return contactsManager.hasSignalAccount(for: contactThread.contactAddress)
    }

    private var disappearingMessagesDurations: [NSNumber] {
        return OWSDisappearingMessagesConfiguration.validDurationsSeconds()
    }

    // A local feature flag.
    private var shouldShowColorPicker: Bool {
        return false
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        if isGroupThread {
            self.title = NSLocalizedString(
                "CONVERSATION_SETTINGS_GROUP_INFO_TITLE", comment: "Navbar title when viewing settings for a group thread")
        } else {
            self.title = NSLocalizedString(
                "CONVERSATION_SETTINGS_CONTACT_INFO_TITLE", comment: "Navbar title when viewing settings for a 1-on-1 thread")
        }

        // This will only appear in internal, qa & dev builds.
        if DebugFlags.groupsV2showV2Indicator {
            let indicator = thread.isGroupV2Thread ? "v2" : "v1"
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: indicator, style: .plain, target: nil, action: nil)
        }

        tableView.estimatedRowHeight = 45
        tableView.rowHeight = UITableView.automaticDimension

        disappearingMessagesDurationLabel.setAccessibilityIdentifier(in: self, name: "disappearingMessagesDurationLabel")

        databaseStorage.uiRead { transaction in
            self.disappearingMessagesConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: self.thread, transaction: transaction)
        }

        if shouldShowColorPicker {
            let colorPicker = ColorPicker(thread: self.thread)
            colorPicker.delegate = self
            self.colorPicker = colorPicker
        }

        updateTableContents()

        observeNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if showVerificationOnAppear {
            showVerificationOnAppear = false
            if isGroupThread {
                showGroupMembersView()
            } else {
                showVerificationView()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let selectedPath = tableView.indexPathForSelectedRow {
            // HACK to unselect rows when swiping back
            // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
            tableView.deselectRow(at: selectedPath, animated: animated)
        }

        updateTableContents()
    }

    // MARK: - Helpers

    private let iconSpacing: CGFloat = 12

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
        iconView.autoSetDimensions(to: CGSize(width: kIconViewLength, height: kIconViewLength))
        return iconView
    }

    // MARK: - Table

    private func updateTableContents() {

        let contents = OWSTableContents()
        contents.title = NSLocalizedString("CONVERSATION_SETTINGS", comment: "title for conversation settings screen")

        let isNoteToSelf = thread.isNoteToSelf
        let canEditSharedConversationSettings = self.canEditSharedConversationSettings
        let isLocalUserInConversation = self.isLocalUserInConversation
        let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration = self.disappearingMessagesConfiguration

        // Main section.
        let mainSection = OWSTableSection()
        mainSection.customHeaderView = mainSectionHeader()
        mainSection.customHeaderHeight = 100

        if let contactThread = thread as? TSContactThread,
            contactsManager.supportsContactEditing && !hasExistingContact {
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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

        mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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

        mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
        if !isNoteToSelf && !self.isGroupThread && self.hasExistingContact {
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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

        if canEditSharedConversationSettings {
            let switchAction = #selector(disappearingMessagesSwitchValueDidChange)
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
                topRow.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

                let subtitleLabel = UILabel()
                subtitleLabel.text = NSLocalizedString(
                    "DISAPPEARING_MESSAGES_DESCRIPTION", comment: "subheading in conversation settings")
                subtitleLabel.textColor = Theme.primaryTextColor
                subtitleLabel.font = .ows_dynamicTypeCaption1
                subtitleLabel.numberOfLines = 0
                subtitleLabel.lineBreakMode = .byWordWrapping
                cell.contentView.addSubview(subtitleLabel)
                subtitleLabel.autoPinEdge(.top, to: .bottom, of: topRow, withOffset: 8)
                subtitleLabel.autoPinEdge(.leading, to: .leading, of: rowLabel)
                subtitleLabel.autoPinTrailingToSuperviewMargin()
                subtitleLabel.autoPinBottomToSuperviewMargin()

                switchView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages_switch")
                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")

                return cell
                },
                                         customRowHeight: UITableView.automaticDimension,
                                         actionBlock: nil))

            if disappearingMessagesConfiguration.isEnabled {
                let sliderAction = #selector(durationSliderDidChange)
                mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
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
        }

        if shouldShowColorPicker {
            mainSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let colorName = self.thread.conversationColorName
                let currentColor = OWSConversationColor.conversationColorOrDefault(colorName: colorName).themeColor
                let title = NSLocalizedString("CONVERSATION_SETTINGS_CONVERSATION_COLOR",
                                              comment: "Label for table cell which leads to picking a new conversation color")
                return self.buildCell(name: title,
                                      icon: .colorPalette,
                                      disclosureIconColor: currentColor,
                                      accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "conversation_color"))
                },
                                         actionBlock: { [weak self] in
                                            self?.showColorPicker()
            }))
        }

        contents.addSection(mainSection)

        // Group settings section.

        if isGroupThread {
            var groupItems = [OWSTableItem]()

            if canEditSharedConversationSettings {
                groupItems.append(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = self.buildDisclosureCell(name: NSLocalizedString("EDIT_GROUP_ACTION",
                                                                                comment: "table cell label in conversation settings"),
                                                        icon: .settingsEditGroup,
                                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "edit_group"))
                    return cell
                    },
                                               actionBlock: { [weak self] in
                                                self?.showUpdateGroupView(mode: .default)
                }))
            }

            if isLocalUserInConversation {
                groupItems += [
                    OWSTableItem(customCellBlock: { [weak self] in
                        guard let self = self else {
                            owsFailDebug("Missing self")
                            return OWSTableItem.newCell()
                        }

                        let cell = self.buildDisclosureCell(name: NSLocalizedString("LIST_GROUP_MEMBERS_ACTION",
                                                                                    comment: "table cell label in conversation settings"),
                                                            icon: .settingsShowGroup,
                                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "group_members"))
                        return cell
                        },
                                 actionBlock: { [weak self] in
                                    self?.showGroupMembersView()
                    }),
                    OWSTableItem(customCellBlock: { [weak self] in
                        guard let self = self else {
                            owsFailDebug("Missing self")
                            return OWSTableItem.newCell()
                        }

                        let cell = self.buildDisclosureCell(name: NSLocalizedString("LEAVE_GROUP_ACTION",
                                                                                    comment: "table cell label in conversation settings"),
                                                            icon: .settingsLeaveGroup,
                                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group"))
                        return cell
                        },
                                 actionBlock: { [weak self] in
                                    self?.didTapLeaveGroup()
                    })
                ]
            }

            contents.addSection(OWSTableSection(title: NSLocalizedString("GROUP_MANAGEMENT_SECTION",
                                                                         comment: "Conversation settings table section title"),
                                                items: groupItems))
        }

        // Mute thread section.

        if !isNoteToSelf {
            let notificationsSection = OWSTableSection()
            // We need a section header to separate the notifications UI from the group settings UI.
            notificationsSection.headerTitle = NSLocalizedString(
                "SETTINGS_SECTION_NOTIFICATIONS", comment: "Label for the notifications section of conversation settings view.")

            notificationsSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                OWSTableItem.configureCell(cell)
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.accessoryType = .disclosureIndicator

                let iconView = self.imageView(forIcon: .settingsMessageSound)

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("SETTINGS_ITEM_NOTIFICATION_SOUND",
                                                  comment: "Label for settings view that allows user to change the notification sound.")
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = .ows_dynamicTypeBody
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow =
                    UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacing
                contentRow.alignment = .center
                cell.contentView.addSubview(contentRow)
                contentRow.autoPinEdgesToSuperviewMargins()

                let sound = OWSSounds.notificationSound(for: self.thread)
                cell.detailTextLabel?.text = OWSSounds.displayName(for: sound)

                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "notifications")

                return cell
                },
                                                  customRowHeight: UITableView.automaticDimension,
                                                  actionBlock: { [weak self] in
                                                    guard let self = self else {
                                                        owsFailDebug("Missing self")
                                                        return
                                                    }
                                                    let vc = OWSSoundSettingsViewController()
                                                    vc.thread = self.thread
                                                    self.navigationController?.pushViewController(vc, animated: true)
            }))

            notificationsSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return OWSTableItem.newCell()
                }

                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                OWSTableItem.configureCell(cell)
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true
                cell.accessoryType = .disclosureIndicator

                let iconView = self.imageView(forIcon: .settingsMuted)

                let rowLabel = UILabel()
                rowLabel.text = NSLocalizedString("CONVERSATION_SETTINGS_MUTE_LABEL",
                                                  comment: "label for 'mute thread' cell in conversation settings")
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = .ows_dynamicTypeBody
                rowLabel.lineBreakMode = .byTruncatingTail

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

                let contentRow =
                    UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = self.iconSpacing
                contentRow.alignment = .center
                cell.contentView.addSubview(contentRow)
                contentRow.autoPinEdgesToSuperviewMargins()

                cell.detailTextLabel?.text = muteStatus

                cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mute")

                return cell
                },
                                                  customRowHeight: UITableView.automaticDimension,
                                                  actionBlock: { [weak self] in
                                                    self?.showMuteUnmuteActionSheet()
            }))
            notificationsSection.footerTitle = NSLocalizedString(
                "MUTE_BEHAVIOR_EXPLANATION", comment: "An explanation of the consequences of muting a thread.")
            contents.addSection(notificationsSection)
        }

        // Block Conversation section.

        if !isNoteToSelf {
            let section = OWSTableSection()
            if isGroupThread {
                section.footerTitle = NSLocalizedString(
                    "BLOCK_GROUP_BEHAVIOR_EXPLANATION", comment: "An explanation of the consequences of blocking a group.")
            } else {
                section.footerTitle = NSLocalizedString(
                    "BLOCK_USER_BEHAVIOR_EXPLANATION", comment: "An explanation of the consequences of blocking another user.")
            }

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
            contents.addSection(section)
        }

        self.contents = contents
    }

    // MARK: -

    private func showAddToSystemContactsActionSheet(contactThread: TSContactThread) {
        let actionSheet = ActionSheetController()
        let createNewTitle = NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                               comment: "Label for 'new contact' button in conversation settings view.")
        actionSheet.addAction(ActionSheetAction(title: createNewTitle,
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    guard let self = self else {
                                                        owsFailDebug("Missing self")
                                                        return
                                                    }
                                                    self.presentContactViewController()
        }))

        let addToExistingTitle = NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                   comment: "Label for 'new contact' button in conversation settings view.")
        actionSheet.addAction(ActionSheetAction(title: addToExistingTitle,
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    guard let self = self else {
                                                        owsFailDebug("Missing self")
                                                        return
                                                    }
                                                    self.presentAddToContactViewController(address:
                                                        contactThread.contactAddress)
        }))

        self.presentActionSheet(actionSheet)
    }

    // MARK: -

    private func mainSectionHeader() -> UIView {
        let mainSectionHeader = UIView()
        let threadInfoView = UIView.container()
        mainSectionHeader.addSubview(threadInfoView)
        threadInfoView.autoPinWidthToSuperview(withMargin: 16)
        threadInfoView.autoPinHeightToSuperview(withMargin: 16)

        let avatarImage = OWSAvatarBuilder.buildImage(thread: thread, diameter: kLargeAvatarSize)

        let avatarView = AvatarImageView(image: avatarImage)
        self.avatarView = avatarView
        threadInfoView.addSubview(avatarView)
        avatarView.autoVCenterInSuperview()
        avatarView.autoPinLeadingToSuperviewMargin()
        let avatarSize = CGFloat(kLargeAvatarSize)
        avatarView.autoSetDimension(.width, toSize: avatarSize)
        avatarView.autoSetDimension(.height, toSize: avatarSize)

        if isGroupThread && !hasSavedGroupIcon && canEditSharedConversationSettings {
            let cameraImageView = UIImageView()
            cameraImageView.setTemplateImageName("camera-outline-24", tintColor: Theme.secondaryTextAndIconColor)
            threadInfoView.addSubview(cameraImageView)

            cameraImageView.autoSetDimensions(to: CGSize(width: 32, height: 32))
            cameraImageView.contentMode = .center
            cameraImageView.backgroundColor = Theme.backgroundColor
            cameraImageView.layer.cornerRadius = 16
            cameraImageView.layer.shadowColor =
                (Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : Theme.primaryTextColor).cgColor
            cameraImageView.layer.shadowOffset = CGSize(width: 1, height: 1)
            cameraImageView.layer.shadowOpacity = 0.5
            cameraImageView.layer.shadowRadius = 4

            cameraImageView.autoPinTrailing(toEdgeOf: avatarView)
            cameraImageView.autoPinEdge(.bottom, to: .bottom, of: avatarView)
        }

        let threadNameView = UIView.container()
        threadInfoView.addSubview(threadNameView)
        threadNameView.autoVCenterInSuperview()
        threadNameView.autoPinTrailingToSuperviewMargin()
        threadNameView.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 16)

        let threadTitleLabel = UILabel()
        threadTitleLabel.text = self.threadName
        threadTitleLabel.textColor = Theme.primaryTextColor
        threadTitleLabel.font = .ows_dynamicTypeTitle2
        threadTitleLabel.lineBreakMode = .byTruncatingTail
        threadNameView.addSubview(threadTitleLabel)
        threadTitleLabel.autoPinEdge(toSuperviewEdge: .top)
        threadTitleLabel.autoPinWidthToSuperview()

        var lastTitleView = threadTitleLabel

        let kSubtitlePointSize: CGFloat = 12
        let addSubtitle = { (subtitle: NSAttributedString) in
            let subtitleLabel = UILabel()
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            subtitleLabel.font = UIFont.ows_regularFont(withSize: kSubtitlePointSize)
            subtitleLabel.attributedText = subtitle
            subtitleLabel.lineBreakMode = .byTruncatingTail
            threadNameView.addSubview(subtitleLabel)
            subtitleLabel.autoPinEdge(.top, to: .bottom, of: lastTitleView)
            subtitleLabel.autoPinLeadingToSuperviewMargin()
            lastTitleView = subtitleLabel
        }

        if let contactThread = thread as? TSContactThread {
            let threadName = contactsManager.displayNameWithSneakyTransaction(thread: contactThread)
            let recipientAddress = contactThread.contactAddress
            if let phoneNumber = recipientAddress.phoneNumber {
                let formattedPhoneNumber =
                    PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
                if threadName != formattedPhoneNumber {
                    let subtitle = NSAttributedString(string: formattedPhoneNumber)
                    addSubtitle(subtitle)
                }
            }

            if let username = (databaseStorage.uiRead { transaction in
                return self.profileManager.username(for: recipientAddress, transaction: transaction)
            }),
                username.count > 0 {
                if let formattedUsername = CommonFormats.formatUsername(username),
                    threadName != formattedUsername {
                    addSubtitle(NSAttributedString(string: formattedUsername))
                }
            }

            if !RemoteConfig.messageRequests
                && !contactsManager.hasNameInSystemContacts(for: recipientAddress) {
                if let profileName = contactsManager.formattedProfileName(for: recipientAddress) {
                    addSubtitle(NSAttributedString(string: profileName))
                }
            }

            #if TESTABLE_BUILD
            let uuidText = String(format: "UUID: %@", contactThread.contactAddress.uuid?.uuidString ?? "Unknown")
            addSubtitle(NSAttributedString(string: uuidText))
            #endif

            let isVerified = identityManager.verificationState(for: recipientAddress) == .verified
            if isVerified {
                let subtitle = NSMutableAttributedString()
                // "checkmark"
                subtitle.append("\u{f00c} ",
                                attributes: [
                                    .font: UIFont.ows_fontAwesomeFont(kSubtitlePointSize)
                ])
                subtitle.append(NSLocalizedString("PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                  comment: "Badge indicating that the user is verified."))
                addSubtitle(subtitle)
            }
        }

        // TODO Message Request: In order to debug the profile is getting shared in the right moments,
        // display the thread whitelist state in settings. Eventually we can probably delete this.
        #if DEBUG
        let isThreadInProfileWhitelist =
            databaseStorage.uiRead { transaction in
                return self.profileManager.isThread(inProfileWhitelist: self.thread, transaction: transaction)
        }
        let hasSharedProfile = String(format: "Whitelisted: %@", isThreadInProfileWhitelist ? "Yes" : "No")
        addSubtitle(NSAttributedString(string: hasSharedProfile))
        #endif

        lastTitleView.autoPinEdge(toSuperviewEdge: .bottom)

        if canEditSharedConversationSettings {
            mainSectionHeader.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(conversationNameTouched)))
        }
        mainSectionHeader.isUserInteractionEnabled = true
        mainSectionHeader.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "mainSectionHeader")

        return mainSectionHeader
    }

    @objc func conversationNameTouched(sender: UIGestureRecognizer) {
        if !canEditSharedConversationSettings {
            owsFailDebug("failure: !self.canEditSharedConversationSettings")
            return
        }
        guard let avatarView = avatarView else {
            owsFailDebug("Missing avatarView.")
            return
        }

        if sender.state == .recognized {
            if isGroupThread {
                let location = sender.location(in: avatarView)
                if avatarView.bounds.contains(location) {
                    showUpdateGroupView(mode: .editGroupAvatar)
                } else {
                    showUpdateGroupView(mode: .editGroupName)
                }
            } else {
                if contactsManager.supportsContactEditing {
                    presentContactViewController()
                }
            }
        }
    }

    private var hasUnsavedChangesToDisappearingMessagesConfiguration: Bool {
        return databaseStorage.uiRead { transaction in
            if let groupThread = self.thread as? TSGroupThread {
                guard let latestThread = TSGroupThread.fetch(groupId: groupThread.groupModel.groupId, transaction: transaction) else {
                    // Thread no longer exists.
                    return false
                }
                guard latestThread.isLocalUserInGroup else {
                    // Local user is no longer in group, e.g. perhaps they just blocked it.
                    return false
                }
            }
            return self.disappearingMessagesConfiguration.hasChanged(with: transaction)
        }
    }

    // MARK: - Actions

    private func showShareProfileAlert() {
        profileManager.presentAddThread(toProfileWhitelist: thread,
                                        from: self) {
                                            self.updateTableContents()
        }
    }

    private func showVerificationView() {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let contactAddress = contactThread.contactAddress
        assert(contactAddress.isValid)
        FingerprintViewController.present(from: self, address: contactAddress)
    }

    private func showGroupMembersView() {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let showGroupMembersViewController = ShowGroupMembersViewController()
        showGroupMembersViewController.config(with: groupThread)
        navigationController?.pushViewController(showGroupMembersViewController, animated: true)
    }

    private func showUpdateGroupView(mode: UpdateGroupMode) {

        if !canEditSharedConversationSettings {
            owsFailDebug("failure: !self.canEditSharedConversationSettings")
            return
        }

        assert(conversationSettingsViewDelegate != nil)

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let updateGroupViewController = UpdateGroupViewController(groupThread: groupThread, mode: mode)
        updateGroupViewController.conversationSettingsViewDelegate = self.conversationSettingsViewDelegate
        navigationController?.pushViewController(updateGroupViewController, animated: true)
    }

    private func presentContactViewController() {
        if !contactsManager.supportsContactEditing {
            owsFailDebug("Contact editing not supported")
            return
        }
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        guard let contactViewController =
            contactsViewHelper?.contactViewController(for: contactThread.contactAddress, editImmediately: true) else {
                owsFailDebug("Unexpectedly missing contact VC")
                return
        }

        contactViewController.delegate = self
        navigationController?.pushViewController(contactViewController, animated: true)
    }

    private func presentAddToContactViewController(address: SignalServiceAddress) {

        if !contactsManager.supportsContactEditing {
            // Should not expose UI that lets the user get here.
            owsFailDebug("Contact editing not supported.")
            return
        }

        if !contactsManager.isSystemContactsAuthorized {
            contactsViewHelper?.presentMissingContactAccessAlertController(from: self)
            return
        }

        let viewController = OWSAddToContactViewController()
        viewController.configure(with: address)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func didTapLeaveGroup() {

        let alert = ActionSheetController(title: NSLocalizedString("CONFIRM_LEAVE_GROUP_TITLE", comment: "Alert title"),
                                          message: NSLocalizedString("CONFIRM_LEAVE_GROUP_DESCRIPTION", comment: "Alert body"))

        let leaveAction = ActionSheetAction(title: NSLocalizedString("LEAVE_BUTTON_TITLE", comment: "Confirmation button within contextual alert"),
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group_confirm"),
                                            style: .destructive) { _ in
                                                self.leaveGroup()
        }
        alert.addAction(leaveAction)
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    private func leaveGroup() {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(groupThread: groupThread, fromViewController: self) {
            self.navigationController?.popViewController(animated: true)
        }
    }

    @objc
    func disappearingMessagesSwitchValueDidChange(_ sender: UISwitch) {
        assert(canEditSharedConversationSettings)

        toggleDisappearingMessages(sender.isOn)

        updateTableContents()
    }

    @objc
    func blockConversationSwitchDidChange(_ sender: UISwitch) {

        let isCurrentlyBlocked = blockingManager.isThreadBlocked(thread)

        if sender.isOn {
            if isCurrentlyBlocked {
                owsFailDebug("Already blocked.")
                return
            }
            BlockListUIUtils.showBlockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return
                }

                // Update switch state if user cancels action.
                sender.isOn = isBlocked

                self.updateTableContents()
            }
        } else {
            if !isCurrentlyBlocked {
                owsFailDebug("Not blocked.")
                return
            }
            BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
                guard let self = self else {
                    owsFailDebug("Missing self")
                    return
                }
                // Update switch state if user cancels action.
                sender.isOn = isBlocked

                self.updateTableContents()
            }
        }
    }

    private func toggleDisappearingMessages(_ flag: Bool) {
        assert(canEditSharedConversationSettings)

        self.disappearingMessagesConfiguration = self.disappearingMessagesConfiguration.copy(withIsEnabled: flag)

        updateTableContents()
    }

    @objc
    func durationSliderDidChange(_ slider: UISlider) {
        assert(canEditSharedConversationSettings)

        let values = self.disappearingMessagesDurations.map { $0.uint32Value }
        let maxValue = values.count - 1
        let index = Int(slider.value + 0.5).clamp(0, maxValue)
        if !slider.isTracking {
            // Snap the slider to a valid value unless the user
            // is still interacting with the control.
            slider.setValue(Float(index), animated: true)
        }
        guard let durationSeconds = values[safe: index] else {
            owsFailDebug("Invalid index: \(index)")
            return
        }
        self.disappearingMessagesConfiguration =
            self.disappearingMessagesConfiguration.copyAsEnabled(withDurationSeconds: durationSeconds)

        updateDisappearingMessagesDurationLabel()
    }

    private func updateDisappearingMessagesDurationLabel() {
        if disappearingMessagesConfiguration.isEnabled {
            let keepForFormat = NSLocalizedString("KEEP_MESSAGES_DURATION",
                                                  comment: "Slider label embeds {{TIME_AMOUNT}}, e.g. '2 hours'. See *_TIME_AMOUNT strings for examples.")
            disappearingMessagesDurationLabel.text = String(format: keepForFormat, disappearingMessagesConfiguration.durationString)
        } else {
            disappearingMessagesDurationLabel.text
                = NSLocalizedString("KEEP_MESSAGES_FOREVER", comment: "Slider label when disappearing messages is off")
        }

        disappearingMessagesDurationLabel.setNeedsLayout()
        disappearingMessagesDurationLabel.superview?.setNeedsLayout()
    }

    private func showMuteUnmuteActionSheet() {
        // The "unmute" action sheet has no title or message; the
        // action label speaks for itself.
        var title: String?
        var message: String?
        if !thread.isMuted {
            title = NSLocalizedString(
                "CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE", comment: "Title of the 'mute this thread' action sheet.")
            message = NSLocalizedString(
                "MUTE_BEHAVIOR_EXPLANATION", comment: "An explanation of the consequences of muting a thread.")
        }

        let actionSheet = ActionSheetController(title: title, message: message)

        if thread.isMuted {
            let action =
                ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_UNMUTE_ACTION",
                                                           comment: "Label for button to unmute a thread."),
                                  accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "unmute"),
                                  style: .destructive) { [weak self] _ in
                                    guard let self = self else {
                                        owsFailDebug("Missing self")
                                        return
                                    }
                                    self.setThreadMutedUntilDate(nil)
            }
            actionSheet.addAction(action)
        } else {
            #if DEBUG
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_MINUTE_ACTION",
                                                                             comment: "Label for button to mute a thread for a minute."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_minute"),
                                                    style: .destructive) { [weak self] _ in
                                                        guard let self = self else {
                                                            owsFailDebug("Missing self")
                                                            return
                                                        }
                                                        self.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.minute = 1
                                                            return dateComponents
                                                        }
            })
            #endif
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                                                                             comment: "Label for button to mute a thread for a hour."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_hour"),
                                                    style: .destructive) { [weak self] _ in
                                                        guard let self = self else {
                                                            owsFailDebug("Missing self")
                                                            return
                                                        }
                                                        self.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.hour = 1
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                                                                             comment: "Label for button to mute a thread for a day."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_day"),
                                                    style: .destructive) { [weak self] _ in
                                                        guard let self = self else {
                                                            owsFailDebug("Missing self")
                                                            return
                                                        }
                                                        self.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.day = 1
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                                                                             comment: "Label for button to mute a thread for a week."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_week"),
                                                    style: .destructive) { [weak self] _ in
                                                        guard let self = self else {
                                                            owsFailDebug("Missing self")
                                                            return
                                                        }
                                                        self.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.day = 7
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_YEAR_ACTION",
                                                                             comment: "Label for button to mute a thread for a year."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_year"),
                                                    style: .destructive) { [weak self] _ in
                                                        guard let self = self else {
                                                            owsFailDebug("Missing self")
                                                            return
                                                        }
                                                        self.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.year = 1
                                                            return dateComponents
                                                        }
            })
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func setThreadMuted(dateBlock: () -> DateComponents) {
        guard let timeZone = TimeZone(identifier: "UTC") else {
            owsFailDebug("Invalid timezone.")
            return
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let dateComponents = dateBlock()
        guard let mutedUntilDate = calendar.date(byAdding: dateComponents, to: Date()) else {
            owsFailDebug("Couldn't modify date.")
            return
        }
        self.setThreadMutedUntilDate(mutedUntilDate)
    }

    private func setThreadMutedUntilDate(_ value: Date?) {
        databaseStorage.write { transaction in
            self.thread.updateWithMuted(until: value, transaction: transaction)
        }

        updateTableContents()
    }

    private func showMediaGallery() {
        Logger.debug("")

        let tileVC = MediaTileViewController(thread: thread)
        navigationController?.pushViewController(tileVC, animated: true)
    }

    private func tappedConversationSearch() {
        conversationSettingsViewDelegate?.conversationSettingsDidRequestConversationSearch()
    }

    // MARK: - Notifications

    @objc
    private func identityStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
            address.isValid else {
                owsFailDebug("Missing or invalid address.")
                return
        }
        guard let contactThread = thread as? TSContactThread else {
            return
        }

        if contactThread.contactAddress == address {
            updateTableContents()
        }
    }

    @objc
    private func profileWhitelistDidChange(notification: Notification) {
        AssertIsOnMainThread()

        // If profile whitelist just changed, we may need to refresh the view.
        if let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
            let contactThread = thread as? TSContactThread,
            contactThread.contactAddress == address {
            updateTableContents()
        }

        if let groupId = notification.userInfo?[kNSNotificationKey_ProfileGroupId] as? Data,
            let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupId == groupId {
            updateTableContents()
        }
    }
}

// MARK: -

extension ConversationSettingsViewController: ContactsViewHelperDelegate {

    func contactsViewHelperDidUpdateContacts() {
        updateTableContents()
    }
}

// MARK: -

extension ConversationSettingsViewController: CNContactViewControllerDelegate {

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        updateTableContents()
        navigationController?.popToViewController(self, animated: true)
    }
}

// MARK: -

extension ConversationSettingsViewController: ColorPickerDelegate {

    private func showColorPicker() {
        guard let colorPicker = colorPicker else {
            owsFailDebug("Missing colorPicker.")
            return
        }
        let sheetViewController = colorPicker.sheetViewController
        sheetViewController.delegate = self
        self.present(sheetViewController, animated: true) {
            Logger.info("presented sheet view")
        }
    }

    public func colorPicker(_ colorPicker: ColorPicker, didPickConversationColor conversationColor: OWSConversationColor) {
        Logger.debug("picked color: \(conversationColor.name)")
        databaseStorage.write { transaction in
            self.thread.updateConversationColorName(conversationColor.name, transaction: transaction)
        }

        contactsManager.avatarCache.removeAllImages()
        contactsManager.clearColorNameCache()
        updateTableContents()
        conversationSettingsViewDelegate?.conversationColorWasUpdated()

        DispatchQueue.global().async {
            let operation = ConversationConfigurationSyncOperation(thread: self.thread)
            assert(operation.isReady)
            operation.start()
        }
    }
}

// MARK: -

extension ConversationSettingsViewController: SheetViewControllerDelegate {
    public func sheetViewControllerRequestedDismiss(_ sheetViewController: SheetViewController) {
        dismiss(animated: true)
    }
}

// MARK: -

extension ConversationSettingsViewController: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        let result = hasUnsavedChangesToDisappearingMessagesConfiguration
        if result {
            updateDisappearingMessagesConfigurationAndDismiss()
        }
        return result
    }

    private func updateDisappearingMessagesConfigurationAndDismiss() {
        let dmConfiguration: OWSDisappearingMessagesConfiguration = disappearingMessagesConfiguration
        let thread = self.thread

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.updateDisappearingMessagesConfigurationPromise(dmConfiguration,
                                                                                                                thread: thread)
                                                        }.done { _ in
                                                            modalActivityIndicator.dismiss {
                                                                self.navigationController?.popViewController(animated: true)
                                                            }
                                                        }.catch { error in
                                                            switch error {
                                                            case GroupsV2Error.redundantChange:
                                                                // Treat GroupsV2Error.redundantChange as a success.
                                                                modalActivityIndicator.dismiss {
                                                                    self.navigationController?.popViewController(animated: true)
                                                                }
                                                            default:
                                                                owsFailDebug("Could not update group: \(error)")

                                                                modalActivityIndicator.dismiss {
                                                                    UpdateGroupViewController.showUpdateErrorUI(error: error)
                                                                }
                                                            }
                                                        }.retainUntilComplete()
        }
    }

    private func updateDisappearingMessagesConfigurationPromise(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                                thread: TSThread) -> Promise<Void> {

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: thread,
                                                         description: self.logTag)
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                         disappearingMessageToken: dmConfiguration.asToken)
        }
    }
}
