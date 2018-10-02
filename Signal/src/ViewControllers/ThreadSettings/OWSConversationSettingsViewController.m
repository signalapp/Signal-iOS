//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "FingerprintViewController.h"
#import "OWSAddToContactViewController.h"
#import "OWSBlockingManager.h"
#import "OWSSoundSettingsViewController.h"
#import "PhoneNumber.h"
#import "ShowGroupMembersViewController.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "UpdateGroupViewController.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSAvatarBuilder.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSThread.h>

@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN

const CGFloat kIconViewLength = 24;

@interface OWSConversationSettingsViewController () <ContactEditingDelegate,
    ContactsViewHelperDelegate,
    ColorPickerDelegate,
    OWSSheetViewControllerDelegate>

@property (nonatomic) TSThread *thread;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, readonly) YapDatabaseConnection *editingDatabaseConnection;

@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;
@property (nonatomic) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
@property (nullable, nonatomic) MediaGalleryViewController *mediaGalleryViewController;
@property (nonatomic, readonly) TSAccountManager *accountManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) UIImageView *avatarView;
@property (nonatomic, readonly) UILabel *disappearingMessagesDurationLabel;
@property (nonatomic) OWSColorPicker *colorPicker;

@end

#pragma mark -

@implementation OWSConversationSettingsViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _accountManager = [TSAccountManager sharedInstance];
    _contactsManager = Environment.shared.contactsManager;
    _messageSender = SSKEnvironment.shared.messageSender;
    _blockingManager = [OWSBlockingManager sharedManager];
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    [self observeNotifications];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationName_IdentityStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    return [OWSPrimaryStorage sharedManager].dbReadWriteConnection;
}

- (NSString *)threadName
{
    NSString *threadName = self.thread.name;
    if (self.thread.contactIdentifier &&
        [threadName isEqualToString:self.thread.contactIdentifier]) {
        threadName =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:self.thread.contactIdentifier];
    } else if (threadName.length == 0 && [self isGroupThread]) {
        threadName = [MessageStrings newGroupDefaultTitle];
    }
    return threadName;
}

- (BOOL)isGroupThread
{
    return [self.thread isKindOfClass:[TSGroupThread class]];
}

- (void)configureWithThread:(TSThread *)thread uiDatabaseConnection:(YapDatabaseConnection *)uiDatabaseConnection
{
    OWSAssertDebug(thread);
    self.thread = thread;
    self.uiDatabaseConnection = uiDatabaseConnection;

    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        self.title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_CONTACT_INFO_TITLE", @"Navbar title when viewing settings for a 1-on-1 thread");
    } else {
        self.title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_GROUP_INFO_TITLE", @"Navbar title when viewing settings for a group thread");
    }

    [self updateEditButton];
}

- (void)updateEditButton
{
    OWSAssertDebug(self.thread);

    if ([self.thread isKindOfClass:[TSContactThread class]] && self.contactsManager.supportsContactEditing
        && self.hasExistingContact) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"EDIT_TXT", nil)
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(didTapEditButton)];
    }
}

- (BOOL)hasExistingContact
{
    OWSAssertDebug([self.thread isKindOfClass:[TSContactThread class]]);
    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *recipientId = contactThread.contactIdentifier;
    return [self.contactsManager hasSignalAccountForRecipientId:recipientId];
}

#pragma mark - ContactEditingDelegate

- (void)didFinishEditingContact
{
    [self updateTableContents];

    OWSLogDebug(@"");
    [self dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    [self updateTableContents];

    if (contact) {
        // Saving normally returns you to the "Show Contact" view
        // which we're not interested in, so we skip it here. There is
        // an unfortunate blip of the "Show Contact" view on slower devices.
        OWSLogDebug(@"completed editing contact.");
        [self dismissViewControllerAnimated:NO completion:nil];
    } else {
        OWSLogDebug(@"canceled editing contact.");
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.estimatedRowHeight = 45;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    _disappearingMessagesDurationLabel = [UILabel new];

    self.disappearingMessagesDurations = [OWSDisappearingMessagesConfiguration validDurationsSeconds];

    self.disappearingMessagesConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];

    if (!self.disappearingMessagesConfiguration) {
        self.disappearingMessagesConfiguration =
            [[OWSDisappearingMessagesConfiguration alloc] initDefaultWithThreadId:self.thread.uniqueId];
    }

    self.colorPicker = [[OWSColorPicker alloc] initWithThread:self.thread];
    self.colorPicker.delegate = self;

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.showVerificationOnAppear) {
        self.showVerificationOnAppear = NO;
        if (self.isGroupThread) {
            [self showGroupMembersView];
        } else {
            [self showVerificationView];
        }
    }
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    __weak OWSConversationSettingsViewController *weakSelf = self;

    // Main section.

    OWSTableSection *mainSection = [OWSTableSection new];

    mainSection.customHeaderView = [self mainSectionHeader];
    mainSection.customHeaderHeight = @(100.f);

    [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        return [weakSelf disclosureCellWithName:MediaStrings.allMedia iconName:@"actionsheet_camera_roll_black"];
    }
                             actionBlock:^{
                                 [weakSelf showMediaGallery];
                             }]];

    if ([self.thread isKindOfClass:[TSContactThread class]] && self.contactsManager.supportsContactEditing
        && !self.hasExistingContact) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return
                [weakSelf disclosureCellWithName:NSLocalizedString(@"CONVERSATION_SETTINGS_NEW_CONTACT",
                                                     @"Label for 'new contact' button in conversation settings view.")
                                        iconName:@"table_ic_new_contact"];
        }
                                 actionBlock:^{
                                     [weakSelf presentContactViewController];
                                 }]];
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return
                [weakSelf disclosureCellWithName:NSLocalizedString(@"CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                     @"Label for 'new contact' button in conversation settings view.")
                                        iconName:@"table_ic_add_to_existing_contact"];
        }
                                 actionBlock:^{
                                     OWSConversationSettingsViewController *strongSelf = weakSelf;
                                     OWSCAssertDebug(strongSelf);
                                     TSContactThread *contactThread = (TSContactThread *)strongSelf.thread;
                                     NSString *recipientId = contactThread.contactIdentifier;
                                     [strongSelf presentAddToContactViewControllerWithRecipientId:recipientId];
                                 }]];
    }

    if (!self.isGroupThread && self.thread.hasSafetyNumbers) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                disclosureCellWithName:
                    NSLocalizedString(@"VERIFY_PRIVACY",
                        @"Label for button or row which allows users to verify the safety number of another user.")
                              iconName:@"table_ic_not_verified"];
        }
                                 actionBlock:^{
                                     [weakSelf showVerificationView];
                                 }]];
    }

    if ([OWSProfileManager.sharedManager isThreadInProfileWhitelist:self.thread]) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                labelCellWithName:(self.isGroupThread
                                          ? NSLocalizedString(
                                                @"CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_GROUP",
                                                @"Indicates that user's profile has been shared with a group.")
                                          : NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_USER",
                                                @"Indicates that user's profile has been shared with a user."))iconName
                                 :@"table_ic_share_profile"];
        }
                                                       actionBlock:nil]];
    } else {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            UITableViewCell *cell = [weakSelf
                                disclosureCellWithName:
                                    (self.isGroupThread
                                            ? NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_GROUP",
                                                  @"Action that shares user profile with a group.")
                                            : NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_USER",
                                                  @"Action that shares user profile with a user."))
                                              iconName:@"table_ic_share_profile"];
                            cell.userInteractionEnabled = !weakSelf.hasLeftGroup;

                            return cell;
                        }
                        actionBlock:^{
                            [weakSelf showShareProfileAlert];
                        }]];
    }

    [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 OWSConversationSettingsViewController *strongSelf = weakSelf;
                                 OWSCAssertDebug(strongSelf);
                                 cell.preservesSuperviewLayoutMargins = YES;
                                 cell.contentView.preservesSuperviewLayoutMargins = YES;
                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;

                                 NSString *iconName
                                     = (strongSelf.disappearingMessagesConfiguration.isEnabled ? @"ic_timer"
                                                                                               : @"ic_timer_disabled");
                                 UIImageView *iconView = [strongSelf viewForIconWithName:iconName];

                                 UILabel *rowLabel = [UILabel new];
                                 rowLabel.text = NSLocalizedString(
                                     @"DISAPPEARING_MESSAGES", @"table cell label in conversation settings");
                                 rowLabel.textColor = [Theme primaryColor];
                                 rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                                 rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                                 UISwitch *switchView = [UISwitch new];
                                 switchView.on = strongSelf.disappearingMessagesConfiguration.isEnabled;
                                 [switchView addTarget:strongSelf
                                                action:@selector(disappearingMessagesSwitchValueDidChange:)
                                      forControlEvents:UIControlEventValueChanged];

                                 UIStackView *topRow =
                                     [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel, switchView ]];
                                 topRow.spacing = self.iconSpacing;
                                 topRow.alignment = UIStackViewAlignmentCenter;
                                 [cell.contentView addSubview:topRow];
                                 [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                                 UILabel *subtitleLabel = [UILabel new];
                                 subtitleLabel.text = NSLocalizedString(
                                     @"DISAPPEARING_MESSAGES_DESCRIPTION", @"subheading in conversation settings");
                                 subtitleLabel.textColor = [Theme primaryColor];
                                 subtitleLabel.font = [UIFont ows_dynamicTypeCaption1Font];
                                 subtitleLabel.numberOfLines = 0;
                                 subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
                                 [cell.contentView addSubview:subtitleLabel];
                                 [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topRow withOffset:8];
                                 [subtitleLabel autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:rowLabel];
                                 [subtitleLabel autoPinTrailingToSuperviewMargin];
                                 [subtitleLabel autoPinBottomToSuperviewMargin];

                                 cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                                 return cell;
                             }
                                     customRowHeight:UITableViewAutomaticDimension
                                         actionBlock:nil]];

    if (self.disappearingMessagesConfiguration.isEnabled) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            UITableViewCell *cell = [OWSTableItem newCell];
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);
                            cell.preservesSuperviewLayoutMargins = YES;
                            cell.contentView.preservesSuperviewLayoutMargins = YES;
                            cell.selectionStyle = UITableViewCellSelectionStyleNone;

                            UIImageView *iconView = [strongSelf viewForIconWithName:@"ic_timer"];

                            UILabel *rowLabel = strongSelf.disappearingMessagesDurationLabel;
                            [strongSelf updateDisappearingMessagesDurationLabel];
                            rowLabel.textColor = [Theme primaryColor];
                            rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                            // don't truncate useful duration info which is in the tail
                            rowLabel.lineBreakMode = NSLineBreakByTruncatingHead;

                            UIStackView *topRow =
                                [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                            topRow.spacing = self.iconSpacing;
                            topRow.alignment = UIStackViewAlignmentCenter;
                            [cell.contentView addSubview:topRow];
                            [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                            UISlider *slider = [UISlider new];
                            slider.maximumValue = (float)(strongSelf.disappearingMessagesDurations.count - 1);
                            slider.minimumValue = 0;
                            slider.continuous = YES; // NO fires change event only once you let go
                            slider.value = strongSelf.disappearingMessagesConfiguration.durationIndex;
                            [slider addTarget:strongSelf
                                          action:@selector(durationSliderDidChange:)
                                forControlEvents:UIControlEventValueChanged];
                            [cell.contentView addSubview:slider];
                            [slider autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topRow withOffset:6];
                            [slider autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:rowLabel];
                            [slider autoPinTrailingToSuperviewMargin];
                            [slider autoPinBottomToSuperviewMargin];

                            cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                            return cell;
                        }
                                customRowHeight:UITableViewAutomaticDimension
                                    actionBlock:nil]];
    }
    [mainSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^{
                        NSString *colorName = self.thread.conversationColorName;
                        UIColor *currentColor =
                            [OWSConversationColor conversationColorOrDefaultForColorName:colorName].themeColor;
                        NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_CONVERSATION_COLOR",
                            @"Label for table cell which leads to picking a new conversation color");
                        return
                            [weakSelf cellWithName:title iconName:@"ic_color_palette" disclosureIconColor:currentColor];
                    }
                    actionBlock:^{
                        [weakSelf showColorPicker];
                    }]];

    [contents addSection:mainSection];

    // Group settings section.

    if (self.isGroupThread) {
        NSArray *groupItems = @[
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"EDIT_GROUP_ACTION",
                                                             @"table cell label in conversation settings")
                                                iconName:@"table_ic_group_edit"];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
                    return cell;
                }
                actionBlock:^{
                    [weakSelf showUpdateGroupView:UpdateGroupMode_Default];
                }],
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"LIST_GROUP_MEMBERS_ACTION",
                                                             @"table cell label in conversation settings")
                                                iconName:@"table_ic_group_members"];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
                    return cell;
                }
                actionBlock:^{
                    [weakSelf showGroupMembersView];
                }],
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"LEAVE_GROUP_ACTION",
                                                             @"table cell label in conversation settings")
                                                iconName:@"table_ic_group_leave"];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;

                    return cell;
                }
                actionBlock:^{
                    [weakSelf didTapLeaveGroup];
                }],
        ];

        [contents addSection:[OWSTableSection sectionWithTitle:NSLocalizedString(@"GROUP_MANAGEMENT_SECTION",
                                                                   @"Conversation settings table section title")
                                                         items:groupItems]];
    }

    // Mute thread section.

    OWSTableSection *notificationsSection = [OWSTableSection new];
    // We need a section header to separate the notifications UI from the group settings UI.
    notificationsSection.headerTitle = NSLocalizedString(
        @"SETTINGS_SECTION_NOTIFICATIONS", @"Label for the notifications section of conversation settings view.");

    [notificationsSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^{
                        UITableViewCell *cell =
                            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                        [OWSTableItem configureCell:cell];
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;
                        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

                        UIImageView *iconView = [strongSelf viewForIconWithName:@"table_ic_notification_sound"];

                        UILabel *rowLabel = [UILabel new];
                        rowLabel.text = NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                            @"Label for settings view that allows user to change the notification sound.");
                        rowLabel.textColor = [Theme primaryColor];
                        rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                        rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                        UIStackView *contentRow =
                            [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                        contentRow.spacing = self.iconSpacing;
                        contentRow.alignment = UIStackViewAlignmentCenter;
                        [cell.contentView addSubview:contentRow];
                        [contentRow autoPinEdgesToSuperviewMargins];

                        OWSSound sound = [OWSSounds notificationSoundForThread:self.thread];
                        cell.detailTextLabel.text = [OWSSounds displayNameForSound:sound];
                        return cell;
                    }
                    customRowHeight:UITableViewAutomaticDimension
                    actionBlock:^{
                        OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
                        vc.thread = weakSelf.thread;
                        [weakSelf.navigationController pushViewController:vc animated:YES];
                    }]];

    [notificationsSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^{
                        UITableViewCell *cell =
                            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                        [OWSTableItem configureCell:cell];
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;
                        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

                        UIImageView *iconView = [strongSelf viewForIconWithName:@"table_ic_mute_thread"];

                        UILabel *rowLabel = [UILabel new];
                        rowLabel.text = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_LABEL",
                            @"label for 'mute thread' cell in conversation settings");
                        rowLabel.textColor = [Theme primaryColor];
                        rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
                        rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                        NSString *muteStatus = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_NOT_MUTED",
                            @"Indicates that the current thread is not muted.");
                        NSDate *mutedUntilDate = strongSelf.thread.mutedUntilDate;
                        NSDate *now = [NSDate date];
                        if (mutedUntilDate != nil && [mutedUntilDate timeIntervalSinceDate:now] > 0) {
                            NSCalendar *calendar = [NSCalendar currentCalendar];
                            NSCalendarUnit calendarUnits = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
                            NSDateComponents *muteUntilComponents =
                                [calendar components:calendarUnits fromDate:mutedUntilDate];
                            NSDateComponents *nowComponents = [calendar components:calendarUnits fromDate:now];
                            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                            if (nowComponents.year != muteUntilComponents.year
                                || nowComponents.month != muteUntilComponents.month
                                || nowComponents.day != muteUntilComponents.day) {

                                [dateFormatter setDateStyle:NSDateFormatterShortStyle];
                                [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                            } else {
                                [dateFormatter setDateStyle:NSDateFormatterNoStyle];
                                [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                            }

                            muteStatus = [NSString
                                stringWithFormat:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTED_UNTIL_FORMAT",
                                                     @"Indicates that this thread is muted until a given date or time. "
                                                     @"Embeds {{The date or time which the thread is muted until}}."),
                                [dateFormatter stringFromDate:mutedUntilDate]];
                        }

                        UIStackView *contentRow =
                            [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                        contentRow.spacing = self.iconSpacing;
                        contentRow.alignment = UIStackViewAlignmentCenter;
                        [cell.contentView addSubview:contentRow];
                        [contentRow autoPinEdgesToSuperviewMargins];

                        cell.detailTextLabel.text = muteStatus;
                        return cell;
                    }
                    customRowHeight:UITableViewAutomaticDimension
                    actionBlock:^{
                        [weakSelf showMuteUnmuteActionSheet];
                    }]];
    notificationsSection.footerTitle
        = NSLocalizedString(@"MUTE_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of muting a thread.");
    [contents addSection:notificationsSection];

    // Block Conversation section.

    OWSTableSection *section = [OWSTableSection new];
    if (self.thread.isGroupThread) {
        section.footerTitle = NSLocalizedString(
            @"BLOCK_GROUP_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking a group.");
    } else {
        section.footerTitle = NSLocalizedString(
            @"BLOCK_USER_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");
    }

    [section addItem:[OWSTableItem
                         itemWithCustomCellBlock:^{
                             OWSConversationSettingsViewController *strongSelf = weakSelf;
                             if (!strongSelf) {
                                 return [UITableViewCell new];
                             }

                             NSString *cellTitle;
                             if (self.thread.isGroupThread) {
                                 cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_GROUP",
                                     @"table cell label in conversation settings");
                             } else {
                                 cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_USER",
                                     @"table cell label in conversation settings");
                             }
                             UITableViewCell *cell =
                                 [strongSelf disclosureCellWithName:cellTitle iconName:@"table_ic_block"];

                             cell.selectionStyle = UITableViewCellSelectionStyleNone;

                             UISwitch *blockConversationSwitch = [UISwitch new];
                             blockConversationSwitch.on = [strongSelf.blockingManager isThreadBlocked:self.thread];
                             [blockConversationSwitch addTarget:strongSelf
                                                         action:@selector(blockConversationSwitchDidChange:)
                                               forControlEvents:UIControlEventValueChanged];
                             cell.accessoryView = blockConversationSwitch;
                             return cell;
                         }
                                     actionBlock:nil]];
    [contents addSection:section];

    self.contents = contents;
}

- (CGFloat)iconSpacing
{
    return 12.f;
}

- (UITableViewCell *)cellWithName:(NSString *)name
                         iconName:(NSString *)iconName
              disclosureIconColor:(UIColor *)disclosureIconColor
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    OWSColorPickerAccessoryView *accessoryView =
        [[OWSColorPickerAccessoryView alloc] initWithColor:disclosureIconColor];
    [accessoryView sizeToFit];
    cell.accessoryView = accessoryView;

    return cell;
}

- (UITableViewCell *)cellWithName:(NSString *)name iconName:(NSString *)iconName
{
    OWSAssertDebug(iconName.length > 0);
    UIImageView *iconView = [self viewForIconWithName:iconName];
    return [self cellWithName:name iconView:iconView];
}

- (UITableViewCell *)cellWithName:(NSString *)name iconView:(UIView *)iconView
{
    OWSAssertDebug(name.length > 0);

    UITableViewCell *cell = [OWSTableItem newCell];
    cell.preservesSuperviewLayoutMargins = YES;
    cell.contentView.preservesSuperviewLayoutMargins = YES;

    UILabel *rowLabel = [UILabel new];
    rowLabel.text = name;
    rowLabel.textColor = [Theme primaryColor];
    rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
    rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *contentRow = [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
    contentRow.spacing = self.iconSpacing;

    [cell.contentView addSubview:contentRow];
    [contentRow autoPinEdgesToSuperviewMargins];

    return cell;
}

- (UITableViewCell *)disclosureCellWithName:(NSString *)name iconName:(NSString *)iconName
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)labelCellWithName:(NSString *)name iconName:(NSString *)iconName
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UIView *)mainSectionHeader
{
    UIView *mainSectionHeader = [UIView new];
    UIView *threadInfoView = [UIView containerView];
    [mainSectionHeader addSubview:threadInfoView];
    [threadInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [threadInfoView autoPinHeightToSuperviewWithMargin:16.f];

    UIImage *avatarImage = [OWSAvatarBuilder buildImageForThread:self.thread diameter:kLargeAvatarSize];
    OWSAssertDebug(avatarImage);

    AvatarImageView *avatarView = [[AvatarImageView alloc] initWithImage:avatarImage];
    _avatarView = avatarView;
    [threadInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kLargeAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kLargeAvatarSize];

    UIView *threadNameView = [UIView containerView];
    [threadInfoView addSubview:threadNameView];
    [threadNameView autoVCenterInSuperview];
    [threadNameView autoPinTrailingToSuperviewMargin];
    [threadNameView autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];

    UILabel *threadTitleLabel = [UILabel new];
    threadTitleLabel.text = self.threadName;
    threadTitleLabel.textColor = [Theme primaryColor];
    threadTitleLabel.font = [UIFont ows_dynamicTypeTitle2Font];
    threadTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [threadNameView addSubview:threadTitleLabel];
    [threadTitleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [threadTitleLabel autoPinWidthToSuperview];

    __block UIView *lastTitleView = threadTitleLabel;

    if (![self isGroupThread]) {
        const CGFloat kSubtitlePointSize = 12.f;
        void (^addSubtitle)(NSAttributedString *) = ^(NSAttributedString *subtitle) {
            UILabel *subtitleLabel = [UILabel new];
            subtitleLabel.textColor = [Theme secondaryColor];
            subtitleLabel.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
            subtitleLabel.attributedText = subtitle;
            subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [threadNameView addSubview:subtitleLabel];
            [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastTitleView];
            [subtitleLabel autoPinLeadingToSuperviewMargin];
            lastTitleView = subtitleLabel;
        };

        NSString *recipientId = self.thread.contactIdentifier;

        BOOL hasName = ![self.thread.name isEqualToString:recipientId];
        if (hasName) {
            NSAttributedString *subtitle = [[NSAttributedString alloc]
                initWithString:[PhoneNumber
                                   bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId]];
            addSubtitle(subtitle);
        } else {
            NSString *_Nullable profileName = [self.contactsManager formattedProfileNameForRecipientId:recipientId];
            if (profileName) {
                addSubtitle([[NSAttributedString alloc] initWithString:profileName]);
            }
        }

        BOOL isVerified = [[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            == OWSVerificationStateVerified;
        if (isVerified) {
            NSMutableAttributedString *subtitle = [NSMutableAttributedString new];
            // "checkmark"
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:LocalizationNotNeeded(@"\uf00c ")
                                                     attributes:@{
                                                         NSFontAttributeName :
                                                             [UIFont ows_fontAwesomeFont:kSubtitlePointSize],
                                                     }]];
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                                    @"Badge indicating that the user is verified.")]];
            addSubtitle(subtitle);
        }
    }

    [lastTitleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [mainSectionHeader
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(conversationNameTouched:)]];
    mainSectionHeader.userInteractionEnabled = YES;

    return mainSectionHeader;
}

- (void)conversationNameTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        if (self.isGroupThread) {
            CGPoint location = [sender locationInView:self.avatarView];
            if (CGRectContainsPoint(self.avatarView.bounds, location)) {
                [self showUpdateGroupView:UpdateGroupMode_EditGroupAvatar];
            } else {
                [self showUpdateGroupView:UpdateGroupMode_EditGroupName];
            }
        } else {
            if (self.contactsManager.supportsContactEditing) {
                [self presentContactViewController];
            }
        }
    }
}

- (UIImageView *)viewForIconWithName:(NSString *)iconName
{
    UIImage *icon = [UIImage imageNamed:iconName];

    OWSAssertDebug(icon);
    UIImageView *iconView = [UIImageView new];
    iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iconView.tintColor = [Theme secondaryColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.minificationFilter = kCAFilterTrilinear;
    iconView.layer.magnificationFilter = kCAFilterTrilinear;

    [iconView autoSetDimensionsToSize:CGSizeMake(kIconViewLength, kIconViewLength)];

    return iconView;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    NSIndexPath *_Nullable selectedPath = [self.tableView indexPathForSelectedRow];
    if (selectedPath) {
        // HACK to unselect rows when swiping back
        // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
        [self.tableView deselectRowAtIndexPath:selectedPath animated:animated];
    }

    [self updateTableContents];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    if (self.disappearingMessagesConfiguration.isNewRecord && !self.disappearingMessagesConfiguration.isEnabled) {
        // don't save defaults, else we'll unintentionally save the configuration and notify the contact.
        return;
    }

    if (self.disappearingMessagesConfiguration.dictionaryValueDidChange) {
        [self.disappearingMessagesConfiguration save];
        OWSDisappearingConfigurationUpdateInfoMessage *infoMessage =
            [[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                     initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                thread:self.thread
                         configuration:self.disappearingMessagesConfiguration
                   createdByRemoteName:nil
                createdInExistingGroup:NO];
        [infoMessage save];

        [OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob
            runWithConfiguration:self.disappearingMessagesConfiguration
                          thread:self.thread
                   messageSender:self.messageSender];
    }
}

#pragma mark - Actions

- (void)showShareProfileAlert
{
    [OWSProfileManager.sharedManager presentAddThreadToProfileWhitelist:self.thread
                                                     fromViewController:self
                                                                success:^{
                                                                    [self updateTableContents];
                                                                }];
}

- (void)showVerificationView
{
    NSString *recipientId = self.thread.contactIdentifier;
    OWSAssertDebug(recipientId.length > 0);

    [FingerprintViewController presentFromViewController:self recipientId:recipientId];
}

- (void)showGroupMembersView
{
    ShowGroupMembersViewController *showGroupMembersViewController = [ShowGroupMembersViewController new];
    [showGroupMembersViewController configWithThread:(TSGroupThread *)self.thread];
    [self.navigationController pushViewController:showGroupMembersViewController animated:YES];
}

- (void)showUpdateGroupView:(UpdateGroupMode)mode
{
    OWSAssertDebug(self.conversationSettingsViewDelegate);

    UpdateGroupViewController *updateGroupViewController = [UpdateGroupViewController new];
    updateGroupViewController.conversationSettingsViewDelegate = self.conversationSettingsViewDelegate;
    updateGroupViewController.thread = (TSGroupThread *)self.thread;
    updateGroupViewController.mode = mode;
    [self.navigationController pushViewController:updateGroupViewController animated:YES];
}

- (void)presentContactViewController
{
    if (!self.contactsManager.supportsContactEditing) {
        OWSFailDebug(@"Contact editing not supported");
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", [self.thread class]);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    [self.contactsViewHelper presentContactViewControllerForRecipientId:contactThread.contactIdentifier
                                                     fromViewController:self
                                                        editImmediately:YES];
}

- (void)presentAddToContactViewControllerWithRecipientId:(NSString *)recipientId
{
    if (!self.contactsManager.supportsContactEditing) {
        // Should not expose UI that lets the user get here.
        OWSFailDebug(@"Contact editing not supported.");
        return;
    }

    if (!self.contactsManager.isSystemContactsAuthorized) {
        [self.contactsViewHelper presentMissingContactAccessAlertControllerFromViewController:self];
        return;
    }

    OWSAddToContactViewController *viewController = [OWSAddToContactViewController new];
    [viewController configureWithRecipientId:recipientId];
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)didTapEditButton
{
    [self presentContactViewController];
}

- (void)didTapLeaveGroup
{
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRM_LEAVE_GROUP_TITLE", @"Alert title")
                                            message:NSLocalizedString(@"CONFIRM_LEAVE_GROUP_DESCRIPTION", @"Alert body")
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *leaveAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"LEAVE_BUTTON_TITLE", @"Confirmation button within contextual alert")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    [self leaveGroup];
                }];
    [alertController addAction:leaveAction];
    [alertController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (BOOL)hasLeftGroup
{
    if (self.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        BOOL inGroup = [groupThread.groupModel.groupMemberIds containsObject:TSAccountManager.localNumber];
        return !inGroup;
    }

    return NO;
}

- (void)leaveGroup
{
    TSGroupThread *gThread = (TSGroupThread *)self.thread;
    TSOutgoingMessage *message =
        [TSOutgoingMessage outgoingMessageInThread:gThread groupMetaMessage:TSGroupMetaMessageQuit expiresInSeconds:0];
    [self.messageSender enqueueMessage:message
        success:^{
            OWSLogInfo(@"Successfully left group.");
        }
        failure:^(NSError *error) {
            OWSLogWarn(@"Failed to leave group with error: %@", error);
        }];


    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [gThread leaveGroupWithTransaction:transaction];
    }];

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)disappearingMessagesSwitchValueDidChange:(UISwitch *)sender
{
    UISwitch *disappearingMessagesSwitch = (UISwitch *)sender;

    [self toggleDisappearingMessages:disappearingMessagesSwitch.isOn];

    [self updateTableContents];
}

- (void)blockConversationSwitchDidChange:(id)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        OWSFailDebug(@"Unexpected sender for block user switch: %@", sender);
    }
    UISwitch *blockConversationSwitch = (UISwitch *)sender;

    BOOL isCurrentlyBlocked = [self.blockingManager isThreadBlocked:self.thread];

    if (blockConversationSwitch.isOn) {
        OWSAssertDebug(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockThreadActionSheet:self.thread
                                  fromViewController:self
                                     blockingManager:self.blockingManager
                                     contactsManager:self.contactsManager
                                       messageSender:self.messageSender
                                     completionBlock:^(BOOL isBlocked) {
                                         // Update switch state if user cancels action.
                                         blockConversationSwitch.on = isBlocked;
                                     }];

    } else {
        OWSAssertDebug(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockThreadActionSheet:self.thread
                                    fromViewController:self
                                       blockingManager:_blockingManager
                                       contactsManager:_contactsManager
                                       completionBlock:^(BOOL isBlocked) {
                                           // Update switch state if user cancels action.
                                           blockConversationSwitch.on = isBlocked;
                                       }];
    }
}

- (void)toggleDisappearingMessages:(BOOL)flag
{
    self.disappearingMessagesConfiguration.enabled = flag;

    [self updateTableContents];
}

- (void)durationSliderDidChange:(UISlider *)slider
{
    // snap the slider to a valid value
    NSUInteger index = (NSUInteger)(slider.value + 0.5);
    [slider setValue:index animated:YES];
    NSNumber *numberOfSeconds = self.disappearingMessagesDurations[index];
    self.disappearingMessagesConfiguration.durationSeconds = [numberOfSeconds unsignedIntValue];

    [self updateDisappearingMessagesDurationLabel];
}

- (void)updateDisappearingMessagesDurationLabel
{
    if (self.disappearingMessagesConfiguration.isEnabled) {
        NSString *keepForFormat = NSLocalizedString(@"KEEP_MESSAGES_DURATION",
            @"Slider label embeds {{TIME_AMOUNT}}, e.g. '2 hours'. See *_TIME_AMOUNT strings for examples.");
        self.disappearingMessagesDurationLabel.text =
            [NSString stringWithFormat:keepForFormat, self.disappearingMessagesConfiguration.durationString];
    } else {
        self.disappearingMessagesDurationLabel.text
            = NSLocalizedString(@"KEEP_MESSAGES_FOREVER", @"Slider label when disappearing messages is off");
    }

    [self.disappearingMessagesDurationLabel setNeedsLayout];
    [self.disappearingMessagesDurationLabel.superview setNeedsLayout];
}

- (void)showMuteUnmuteActionSheet
{
    // The "unmute" action sheet has no title or message; the
    // action label speaks for itself.
    NSString *title = nil;
    NSString *message = nil;
    if (!self.thread.isMuted) {
        title = NSLocalizedString(
            @"CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE", @"Title of the 'mute this thread' action sheet.");
        message = NSLocalizedString(
            @"MUTE_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of muting a thread.");
    }

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (self.thread.isMuted) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_UNMUTE_ACTION",
                                                                   @"Label for button to unmute a thread.")
                                                         style:UIAlertActionStyleDestructive
                                                       handler:^(UIAlertAction *_Nonnull ignore) {
                                                           [weakSelf setThreadMutedUntilDate:nil];
                                                       }];
        [actionSheetController addAction:action];
    } else {
#ifdef DEBUG
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_MINUTE_ACTION",
                                                         @"Label for button to mute a thread for a minute.")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_Nonnull ignore) {
                                                 NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                                 NSCalendar *calendar = [NSCalendar currentCalendar];
                                                 [calendar setTimeZone:timeZone];
                                                 NSDateComponents *dateComponents = [NSDateComponents new];
                                                 [dateComponents setMinute:1];
                                                 NSDate *mutedUntilDate =
                                                     [calendar dateByAddingComponents:dateComponents
                                                                               toDate:[NSDate date]
                                                                              options:0];
                                                 [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                             }]];
#endif
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                                                         @"Label for button to mute a thread for a hour.")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_Nonnull ignore) {
                                                 NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                                 NSCalendar *calendar = [NSCalendar currentCalendar];
                                                 [calendar setTimeZone:timeZone];
                                                 NSDateComponents *dateComponents = [NSDateComponents new];
                                                 [dateComponents setHour:1];
                                                 NSDate *mutedUntilDate =
                                                     [calendar dateByAddingComponents:dateComponents
                                                                               toDate:[NSDate date]
                                                                              options:0];
                                                 [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                                                         @"Label for button to mute a thread for a day.")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_Nonnull ignore) {
                                                 NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                                 NSCalendar *calendar = [NSCalendar currentCalendar];
                                                 [calendar setTimeZone:timeZone];
                                                 NSDateComponents *dateComponents = [NSDateComponents new];
                                                 [dateComponents setDay:1];
                                                 NSDate *mutedUntilDate =
                                                     [calendar dateByAddingComponents:dateComponents
                                                                               toDate:[NSDate date]
                                                                              options:0];
                                                 [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                                                         @"Label for button to mute a thread for a week.")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_Nonnull ignore) {
                                                 NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                                 NSCalendar *calendar = [NSCalendar currentCalendar];
                                                 [calendar setTimeZone:timeZone];
                                                 NSDateComponents *dateComponents = [NSDateComponents new];
                                                 [dateComponents setDay:7];
                                                 NSDate *mutedUntilDate =
                                                     [calendar dateByAddingComponents:dateComponents
                                                                               toDate:[NSDate date]
                                                                              options:0];
                                                 [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_YEAR_ACTION",
                                                         @"Label for button to mute a thread for a year.")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_Nonnull ignore) {
                                                 NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
                                                 NSCalendar *calendar = [NSCalendar currentCalendar];
                                                 [calendar setTimeZone:timeZone];
                                                 NSDateComponents *dateComponents = [NSDateComponents new];
                                                 [dateComponents setYear:1];
                                                 NSDate *mutedUntilDate =
                                                     [calendar dateByAddingComponents:dateComponents
                                                                               toDate:[NSDate date]
                                                                              options:0];
                                                 [weakSelf setThreadMutedUntilDate:mutedUntilDate];
                                             }]];
    }

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)setThreadMutedUntilDate:(nullable NSDate *)value
{
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [self.thread updateWithMutedUntilDate:value transaction:transaction];
    }];
    
    [self updateTableContents];
}

- (void)showMediaGallery
{
    OWSLogDebug(@"in showMediaGallery");

    MediaGalleryViewController *vc =
        [[MediaGalleryViewController alloc] initWithThread:self.thread
                                      uiDatabaseConnection:self.uiDatabaseConnection
                                                   options:MediaGalleryOptionSliderEnabled];

    // although we don't present the mediaGalleryViewController directly, we need to maintain a strong
    // reference to it until we're dismissed.
    self.mediaGalleryViewController = vc;

    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);
    [vc pushTileViewFromNavController:(OWSNavigationController *)self.navigationController];
}
#pragma mark - Notifications

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssertDebug(recipientId.length > 0);

    if (recipientId.length > 0 && [self.thread isKindOfClass:[TSContactThread class]] &&
        [self.thread.contactIdentifier isEqualToString:recipientId]) {
        [self updateTableContents];
    }
}

#pragma mark - ColorPickerDelegate

- (void)showColorPicker
{
    OWSSheetViewController *sheetViewController = self.colorPicker.sheetViewController;
    sheetViewController.delegate = self;

    [self presentViewController:sheetViewController
                       animated:YES
                     completion:^() {
                         OWSLogInfo(@"presented sheet view");
                     }];
}

- (void)colorPicker:(OWSColorPicker *)colorPicker
    didPickConversationColor:(OWSConversationColor *_Nonnull)conversationColor
{
    OWSLogDebug(@"picked color: %@", conversationColor.name);
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self.thread updateConversationColorName:conversationColor.name transaction:transaction];
    }];

    [self.contactsManager.avatarCache removeAllImages];
    [self updateTableContents];
    [self.conversationSettingsViewDelegate conversationColorWasUpdated];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ConversationConfigurationSyncOperation *operation =
            [[ConversationConfigurationSyncOperation alloc] initWithThread:self.thread];
        OWSAssertDebug(operation.isReady);
        [operation start];
    });
}

#pragma mark - OWSSheetViewController

- (void)sheetViewControllerRequestedDismiss:(OWSSheetViewController *)sheetViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
