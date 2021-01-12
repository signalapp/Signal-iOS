//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewController.h"
#import "BlockListUIUtils.h"



#import "OWSBlockingManager.h"
#import "OWSSoundSettingsViewController.h"

#import "Session-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SessionMessagingKit/Environment.h>

#import <SignalUtilitiesKit/OWSProfileManager.h>
#import <SessionMessagingKit/OWSSounds.h>
#import <SessionMessagingKit/OWSUserProfile.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SignalUtilitiesKit/UIUtil.h>
#import <SessionMessagingKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SessionMessagingKit/OWSDisappearingMessagesConfiguration.h>

#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SessionMessagingKit/TSGroupThread.h>
#import <SessionMessagingKit/TSOutgoingMessage.h>
#import <SessionMessagingKit/TSThread.h>

@import ContactsUI;
@import PromiseKit;

NS_ASSUME_NONNULL_BEGIN

//#define SHOW_COLOR_PICKER

const CGFloat kIconViewLength = 24;

@interface OWSConversationSettingsViewController () <
#ifdef SHOW_COLOR_PICKER
    ColorPickerDelegate,
#endif
    OWSSheetViewControllerDelegate>

@property (nonatomic) TSThread *thread;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, readonly) YapDatabaseConnection *editingDatabaseConnection;

@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;
@property (nonatomic) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
@property (nullable, nonatomic) MediaGallery *mediaGallery;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) UIImageView *avatarView;
@property (nonatomic, readonly) UILabel *disappearingMessagesDurationLabel;
#ifdef SHOW_COLOR_PICKER
@property (nonatomic) OWSColorPicker *colorPicker;
#endif

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

    [self observeNotifications];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

#pragma mark

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

- (nullable NSString *)threadName
{
    NSString *threadName = self.thread.name;
    if (self.thread.contactIdentifier) {
        return [SSKEnvironment.shared.profileManager profileNameForRecipientWithID:self.thread.contactIdentifier avoidingWriteTransaction:YES];
    } else if (threadName.length == 0 && [self isGroupThread]) {
        threadName = [MessageStrings newGroupDefaultTitle];
    }
    return threadName;
}

- (BOOL)isGroupThread
{
    return [self.thread isKindOfClass:[TSGroupThread class]];
}

- (BOOL)isOpenGroup
{
    if ([self isGroupThread]) {
        TSGroupThread *thread = (TSGroupThread *)self.thread;
        return thread.isOpenGroup;
    }
    return false;
}

-(BOOL)isClosedGroup
{
    if (self.isGroupThread) {
        TSGroupThread *thread = (TSGroupThread *)self.thread;
        return thread.groupModel.groupType == closedGroup;
    }
    return false;
}

- (void)configureWithThread:(TSThread *)thread uiDatabaseConnection:(YapDatabaseConnection *)uiDatabaseConnection
{
    OWSAssertDebug(thread);
    self.thread = thread;
    self.uiDatabaseConnection = uiDatabaseConnection;
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

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.estimatedRowHeight = 45;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    _disappearingMessagesDurationLabel = [UILabel new];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _disappearingMessagesDurationLabel);

    self.disappearingMessagesDurations = [OWSDisappearingMessagesConfiguration validDurationsSeconds];

    self.disappearingMessagesConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];

    if (!self.disappearingMessagesConfiguration) {
        self.disappearingMessagesConfiguration =
            [[OWSDisappearingMessagesConfiguration alloc] initDefaultWithThreadId:self.thread.uniqueId];
    }

#ifdef SHOW_COLOR_PICKER
    self.colorPicker = [[OWSColorPicker alloc] initWithThread:self.thread];
    self.colorPicker.delegate = self;
#endif

    [self updateTableContents];
    
    NSString *title;
    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        title = NSLocalizedString(@"Settings", @"");
    } else {
        title = NSLocalizedString(@"Group Settings", @"");
    }
    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:title customBackButton:YES];
    self.tableView.backgroundColor = UIColor.clearColor;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.showVerificationOnAppear) {
        self.showVerificationOnAppear = NO;
        if (self.isGroupThread) {
            [self showGroupMembersView];
        }
    }
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    BOOL isNoteToSelf = self.thread.isNoteToSelf;

    __weak OWSConversationSettingsViewController *weakSelf = self;

    // Main section.

    OWSTableSection *mainSection = [OWSTableSection new];

    mainSection.customHeaderView = [self mainSectionHeader];

    if (self.isGroupThread) {
        mainSection.customHeaderHeight = @(147.f);
    } else {
        BOOL isSmallScreen = (UIScreen.mainScreen.bounds.size.height - 568) < 1;
        mainSection.customHeaderHeight = isSmallScreen ? @(201.f) : @(208.f);
    }

    if ([self.thread isKindOfClass:TSContactThread.class]) {
        [mainSection addItem:[OWSTableItem
                                 itemWithCustomCellBlock:^{
                                     return [weakSelf
                                          disclosureCellWithName:@"Copy Session ID"
                                                        iconName:@"ic_copy"
                                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                     OWSConversationSettingsViewController, @"copy_session_id")];
                                 }
                                 actionBlock:^{
                                     [weakSelf copySessionID];
                                 }]];
    }

    [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 return [weakSelf
                                      disclosureCellWithName:MediaStrings.allMedia
                                                    iconName:@"actionsheet_camera_roll_black"
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                 OWSConversationSettingsViewController, @"all_media")];
                             }
                             actionBlock:^{
                                 [weakSelf showMediaGallery];
                             }]];

    [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_SEARCH",
                                     @"Table cell label in conversation settings which returns the user to the "
                                     @"conversation with 'search mode' activated");
                                 return [weakSelf
                                      disclosureCellWithName:title
                                                    iconName:@"conversation_settings_search"
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                 OWSConversationSettingsViewController, @"search")];
                             }
                             actionBlock:^{
                                 [weakSelf tappedConversationSearch];
                             }]];

    if (![self isOpenGroup]) {
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
                                     rowLabel.textColor = LKColors.text;
                                     rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
                                     rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                                     UISwitch *switchView = [UISwitch new];
                                     switchView.on = strongSelf.disappearingMessagesConfiguration.isEnabled;
                                     [switchView addTarget:strongSelf
                                                    action:@selector(disappearingMessagesSwitchValueDidChange:)
                                          forControlEvents:UIControlEventValueChanged];

                                     UIStackView *topRow =
                                         [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel, switchView ]];
                                     topRow.spacing = strongSelf.iconSpacing;
                                     topRow.alignment = UIStackViewAlignmentCenter;
                                     [cell.contentView addSubview:topRow];
                                     [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                                     UILabel *subtitleLabel = [UILabel new];
                                     NSString *displayName;
                                     if (self.thread.isGroupThread) {
                                         displayName = @"the group";
                                     } else {
                                         displayName = [LKUserDisplayNameUtilities getPrivateChatDisplayNameFor:self.thread.contactIdentifier];
                                     }
                                     subtitleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"When enabled, messages between you and %@ will disappear after they have been seen.", ""), displayName];
                                     subtitleLabel.textColor = LKColors.text;
                                     subtitleLabel.font = [UIFont systemFontOfSize:LKValues.smallFontSize];
                                     subtitleLabel.numberOfLines = 0;
                                     subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
                                     [cell.contentView addSubview:subtitleLabel];
                                     [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topRow withOffset:8];
                                     [subtitleLabel autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:rowLabel];
                                     [subtitleLabel autoPinTrailingToSuperviewMargin];
                                     [subtitleLabel autoPinBottomToSuperviewMargin];

                                     cell.userInteractionEnabled = !strongSelf.hasLeftGroup;

                                     cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                         OWSConversationSettingsViewController, @"disappearing_messages");

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
                                rowLabel.textColor = LKColors.text;
                                rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
                                // don't truncate useful duration info which is in the tail
                                rowLabel.lineBreakMode = NSLineBreakByTruncatingHead;

                                UIStackView *topRow =
                                    [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                                topRow.spacing = strongSelf.iconSpacing;
                                topRow.alignment = UIStackViewAlignmentCenter;
                                [cell.contentView addSubview:topRow];
                                [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                                UISlider *slider = [UISlider new];
                                slider.maximumValue = (float)(strongSelf.disappearingMessagesDurations.count - 1);
                                slider.minimumValue = 0;
                                slider.tintColor = LKColors.accent;
                                slider.continuous = NO;
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

                                cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                    OWSConversationSettingsViewController, @"disappearing_messages_duration");

                                return cell;
                            }
                                    customRowHeight:UITableViewAutomaticDimension
                                        actionBlock:nil]];
        }
    }
#ifdef SHOW_COLOR_PICKER
    [mainSection
        addItem:[OWSTableItem
                    itemWithCustomCellBlock:^{
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);

                        ConversationColorName colorName = strongSelf.thread.conversationColorName;
                        UIColor *currentColor =
                            [OWSConversationColor conversationColorOrDefaultForColorName:colorName].themeColor;
                        NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_CONVERSATION_COLOR",
                            @"Label for table cell which leads to picking a new conversation color");
                        return [strongSelf
                                       cellWithName:title
                                           iconName:@"ic_color_palette"
                                disclosureIconColor:currentColor
                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                        OWSConversationSettingsViewController, @"conversation_color")];
                    }
                    actionBlock:^{
                        [weakSelf showColorPicker];
                    }]];
#endif

    [contents addSection:mainSection];

    // Group settings section.

    __block BOOL isUserMember = NO;
    if (self.isGroupThread) {
        NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
        isUserMember = [(TSGroupThread *)self.thread isUserMemberInGroup:userPublicKey];
    }

    if (self.isGroupThread && self.isClosedGroup && isUserMember) {
        if (((TSGroupThread *)self.thread).isClosedGroup) {
            [mainSection addItem:[OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell =
                        [weakSelf disclosureCellWithName:NSLocalizedString(@"EDIT_GROUP_ACTION",
                                                             @"table cell label in conversation settings")
                                                iconName:@"table_ic_group_edit"
                                 accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                             OWSConversationSettingsViewController, @"edit_group")];
                    cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
                    return cell;
                }
                actionBlock:^{
                    [weakSelf editGroup];
                }]
            ];
        }
        [mainSection addItem:[OWSTableItem
            itemWithCustomCellBlock:^{
                UITableViewCell *cell =
                    [weakSelf disclosureCellWithName:NSLocalizedString(@"LEAVE_GROUP_ACTION",
                                                         @"table cell label in conversation settings")
                                            iconName:@"table_ic_group_leave"
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                         OWSConversationSettingsViewController, @"leave_group")];
                cell.userInteractionEnabled = !weakSelf.hasLeftGroup;

                return cell;
            }
            actionBlock:^{
                [weakSelf didTapLeaveGroup];
            }]
        ];
    }
    

    // Mute thread section.

    if (!isNoteToSelf) {
        [mainSection
            addItem:[OWSTableItem
                        itemWithCustomCellBlock:^{
                            UITableViewCell *cell =
                                [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                            [OWSTableItem configureCell:cell];
                            OWSConversationSettingsViewController *strongSelf = weakSelf;
                            OWSCAssertDebug(strongSelf);
                            cell.preservesSuperviewLayoutMargins = YES;
                            cell.contentView.preservesSuperviewLayoutMargins = YES;

                            UIImageView *iconView = [strongSelf viewForIconWithName:@"table_ic_notification_sound"];

                            UILabel *rowLabel = [UILabel new];
                            rowLabel.text = NSLocalizedString(@"SETTINGS_ITEM_NOTIFICATION_SOUND",
                                @"Label for settings view that allows user to change the notification sound.");
                            rowLabel.textColor = LKColors.text;
                            rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
                            rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                            UIStackView *contentRow =
                                [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
                            contentRow.spacing = strongSelf.iconSpacing;
                            contentRow.alignment = UIStackViewAlignmentCenter;
                            [cell.contentView addSubview:contentRow];
                            [contentRow autoPinEdgesToSuperviewMargins];

                            OWSSound sound = [OWSSounds notificationSoundForThread:strongSelf.thread];
                            cell.detailTextLabel.text = [OWSSounds displayNameForSound:sound];

                            cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                OWSConversationSettingsViewController, @"notifications");

                            return cell;
                        }
                        customRowHeight:UITableViewAutomaticDimension
                        actionBlock:^{
                            OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
                            vc.thread = weakSelf.thread;
                            [weakSelf.navigationController pushViewController:vc animated:YES];
                        }]];
        [mainSection
            addItem:
                [OWSTableItem
                    itemWithCustomCellBlock:^{
                        UITableViewCell *cell =
                            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                        [OWSTableItem configureCell:cell];
                        OWSConversationSettingsViewController *strongSelf = weakSelf;
                        OWSCAssertDebug(strongSelf);
                        cell.preservesSuperviewLayoutMargins = YES;
                        cell.contentView.preservesSuperviewLayoutMargins = YES;

                        UIImageView *iconView = [strongSelf viewForIconWithName:@"Mute"];

                        UILabel *rowLabel = [UILabel new];
                        rowLabel.text = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_LABEL",
                            @"label for 'mute thread' cell in conversation settings");
                        rowLabel.textColor = LKColors.text;
                        rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
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
                        contentRow.spacing = strongSelf.iconSpacing;
                        contentRow.alignment = UIStackViewAlignmentCenter;
                        [cell.contentView addSubview:contentRow];
                        [contentRow autoPinEdgesToSuperviewMargins];

                        cell.detailTextLabel.text = muteStatus;

                        cell.accessibilityIdentifier
                            = ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"mute");

                        return cell;
                    }
                    customRowHeight:UITableViewAutomaticDimension
                    actionBlock:^{
                        [weakSelf showMuteUnmuteActionSheet];
                    }]];
    }
    // Block Conversation section.

    if (!isNoteToSelf && [self.thread isKindOfClass:TSContactThread.class]) {
        mainSection.footerTitle = NSLocalizedString(
            @"BLOCK_USER_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");

        [mainSection addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 OWSConversationSettingsViewController *strongSelf = weakSelf;
                                 if (!strongSelf) {
                                     return [UITableViewCell new];
                                 }

                                 NSString *cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_USER",
                                                                         @"table cell label in conversation settings");
                                 UITableViewCell *cell = [strongSelf
                                      disclosureCellWithName:cellTitle
                                                    iconName:@"table_ic_block"
                                     accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                                 OWSConversationSettingsViewController, @"block")];

                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;

                                 UISwitch *blockConversationSwitch = [UISwitch new];
                                 blockConversationSwitch.on =
                                     [strongSelf.blockingManager isThreadBlocked:strongSelf.thread];
                                 [blockConversationSwitch addTarget:strongSelf
                                                             action:@selector(blockConversationSwitchDidChange:)
                                                   forControlEvents:UIControlEventValueChanged];
                                 cell.accessoryView = blockConversationSwitch;

                                 return cell;
                             }
                                         actionBlock:nil]];
    }

    self.contents = contents;
}

- (CGFloat)iconSpacing
{
    return 12.f;
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
    rowLabel.textColor = LKColors.text;
    rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
    rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *contentRow = [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
    contentRow.spacing = self.iconSpacing;

    [cell.contentView addSubview:contentRow];
    [contentRow autoPinEdgesToSuperviewMargins];

    return cell;
}

- (UITableViewCell *)disclosureCellWithName:(NSString *)name
                                   iconName:(NSString *)iconName
                    accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessibilityIdentifier = accessibilityIdentifier;
    return cell;
}

- (UITableViewCell *)labelCellWithName:(NSString *)name
                              iconName:(NSString *)iconName
               accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = accessibilityIdentifier;
    return cell;
}

static CGRect oldframe;

-(void)showProfilePicture:(UITapGestureRecognizer *)tapGesture
{
    LKProfilePictureView *profilePictureView = (LKProfilePictureView *)tapGesture.view;
    UIImage *image = [profilePictureView getProfilePicture];
    if (image == nil) { return; }
    
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIView *backgroundView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    oldframe = [profilePictureView convertRect:profilePictureView.bounds toView:window];
    backgroundView.backgroundColor = [UIColor blackColor];
    backgroundView.alpha = 0;
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:oldframe];
    imageView.image = image;
    imageView.tag = 1;
    imageView.layer.cornerRadius = [UIScreen mainScreen].bounds.size.width / 2;
    imageView.layer.masksToBounds = true;
    [backgroundView addSubview:imageView];
    [window addSubview:backgroundView];
        
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(hideImage:)];
    [backgroundView addGestureRecognizer: tap];
        
    [UIView animateWithDuration:0.25 animations:^{
        imageView.frame = CGRectMake(0,([UIScreen mainScreen].bounds.size.height - oldframe.size.height * [UIScreen mainScreen].bounds.size.width / oldframe.size.width) / 2, [UIScreen mainScreen].bounds.size.width, oldframe.size.height * [UIScreen mainScreen].bounds.size.width / oldframe.size.width);
        backgroundView.alpha = 1;
    } completion:nil];
}

-(void)hideImage:(UITapGestureRecognizer *)tap{
    UIView *backgroundView = tap.view;
    UIImageView *imageView = (UIImageView *)[tap.view viewWithTag:1];
    [UIView animateWithDuration:0.25 animations:^{
        imageView.frame = oldframe;
        backgroundView.alpha = 0;
    } completion:^(BOOL finished) {
        [backgroundView removeFromSuperview];
    }];
}


- (UIView *)mainSectionHeader
{
    UITapGestureRecognizer *profilePictureTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showProfilePicture:)];
    LKProfilePictureView *profilePictureView = [LKProfilePictureView new];
    CGFloat size = LKValues.largeProfilePictureSize;
    profilePictureView.size = size;
    [profilePictureView autoSetDimension:ALDimensionWidth toSize:size];
    [profilePictureView autoSetDimension:ALDimensionHeight toSize:size];
    [profilePictureView addGestureRecognizer:profilePictureTapGestureRecognizer];
    
    UILabel *titleView = [UILabel new];
    titleView.textColor = LKColors.text;
    titleView.font = [UIFont boldSystemFontOfSize:LKValues.largeFontSize];
    titleView.lineBreakMode = NSLineBreakByTruncatingTail;
    titleView.text = (self.threadName != nil && self.threadName.length > 0) ? self.threadName : @"Anonymous";
    
    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ profilePictureView, titleView ]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = LKValues.mediumSpacing;
    stackView.distribution = UIStackViewDistributionEqualCentering; 
    stackView.alignment = UIStackViewAlignmentCenter;
    BOOL isSmallScreen = (UIScreen.mainScreen.bounds.size.height - 568) < 1;
    CGFloat horizontalSpacing = isSmallScreen ? LKValues.largeSpacing : LKValues.veryLargeSpacing;
    stackView.layoutMargins = UIEdgeInsetsMake(LKValues.mediumSpacing, horizontalSpacing, LKValues.mediumSpacing, horizontalSpacing);
    [stackView setLayoutMarginsRelativeArrangement:YES];

    if (!self.isGroupThread) {
        SRCopyableLabel *subtitleView = [SRCopyableLabel new];
        subtitleView.textColor = LKColors.text;
        subtitleView.font = [LKFonts spaceMonoOfSize:LKValues.smallFontSize];
        subtitleView.lineBreakMode = NSLineBreakByCharWrapping;
        subtitleView.numberOfLines = 2;
        subtitleView.text = self.thread.contactIdentifier;
        subtitleView.textAlignment = NSTextAlignmentCenter;
        [stackView addArrangedSubview:subtitleView];
    }
    
    [profilePictureView updateForThread:self.thread];
    
    return stackView;
}

- (UIImageView *)viewForIconWithName:(NSString *)iconName
{
    UIImage *icon = [UIImage imageNamed:iconName];

    OWSAssertDebug(icon);
    UIImageView *iconView = [UIImageView new];
    iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iconView.tintColor = LKColors.text;
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
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self.disappearingMessagesConfiguration saveWithTransaction:transaction];
            OWSDisappearingConfigurationUpdateInfoMessage *infoMessage = [[OWSDisappearingConfigurationUpdateInfoMessage alloc]
                         initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                    thread:self.thread
                             configuration:self.disappearingMessagesConfiguration
                       createdByRemoteName:nil
                    createdInExistingGroup:NO];
            [infoMessage saveWithTransaction:transaction];

            SNExpirationTimerUpdate *expirationTimerUpdate = [SNExpirationTimerUpdate new];
            BOOL isEnabled = self.disappearingMessagesConfiguration.enabled;
            expirationTimerUpdate.duration = isEnabled ? self.disappearingMessagesConfiguration.durationSeconds : 0;
            [SNMessageSender send:expirationTimerUpdate inThread:self.thread usingTransaction:transaction];
        }];
    }
}

#pragma mark - Actions

- (void)showShareProfileAlert
{
    [self.profileManager presentAddThreadToProfileWhitelist:self.thread
                                         fromViewController:self
                                                    success:^{
                                                        [self updateTableContents];
                                                    }];
}

- (void)showGroupMembersView
{
    TSGroupThread *thread = (TSGroupThread *)self.thread;
    LKGroupMembersVC *groupMembersVC = [[LKGroupMembersVC alloc] initWithThread:thread];
    [self.navigationController pushViewController:groupMembersVC animated:YES];
}

- (void)editGroup
{
    LKEditClosedGroupVC *editClosedGroupVC = [[LKEditClosedGroupVC alloc] initWithThreadID:self.thread.uniqueId];
    [self.navigationController pushViewController:editClosedGroupVC animated:YES completion:nil];
}

- (void)didTapLeaveGroup
{
    NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
    NSString *message;
    if ([((TSGroupThread *)self.thread).groupModel.groupAdminIds containsObject:userPublicKey]) {
        message = @"Because you are the creator of this group it will be deleted for everyone. This cannot be undone.";
    } else {
        message = NSLocalizedString(@"CONFIRM_LEAVE_GROUP_DESCRIPTION", @"Alert body");
    }
    
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRM_LEAVE_GROUP_TITLE", @"Alert title")
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *leaveAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"LEAVE_BUTTON_TITLE", @"Confirmation button within contextual alert")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"leave_group_confirm")
                          style:UIAlertActionStyleDestructive
                        handler:^(UIAlertAction *_Nonnull action) {
                            [self leaveGroup];
                        }];
    [alert addAction:leaveAction];
    [alert addAction:[OWSAlerts cancelAction]];

    [self presentAlert:alert];
}

- (BOOL)hasLeftGroup
{
    if (self.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        return !groupThread.isCurrentUserMemberInGroup;
    }

    return NO;
}

- (void)leaveGroup
{
    TSGroupThread *gThread = (TSGroupThread *)self.thread;

    if (gThread.isClosedGroup) {
        NSString *groupPublicKey = [LKGroupUtilities getDecodedGroupID:gThread.groupModel.groupId];
        [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [SNMessageSender leaveClosedGroupWithPublicKey:groupPublicKey using:transaction error:nil];
        }];
    }

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

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (blockConversationSwitch.isOn) {
        OWSAssertDebug(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockThreadActionSheet:self.thread
                                  fromViewController:self
                                     blockingManager:self.blockingManager
                                     completionBlock:^(BOOL isBlocked) {
                                         // Update switch state if user cancels action.
                                         blockConversationSwitch.on = isBlocked;

                                         [weakSelf updateTableContents];
                                     }];

    } else {
        OWSAssertDebug(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockThreadActionSheet:self.thread
                                    fromViewController:self
                                       blockingManager:self.blockingManager
                                       completionBlock:^(BOOL isBlocked) {
                                           // Update switch state if user cancels action.
                                           blockConversationSwitch.on = isBlocked;

                                           [weakSelf updateTableContents];
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
        NSString *keepForFormat = @"Disappear after %@";
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

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:title
                                                                         message:message
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (self.thread.isMuted) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_UNMUTE_ACTION",
                                                                   @"Label for button to unmute a thread.")
                                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"unmute")
                                                         style:UIAlertActionStyleDestructive
                                                       handler:^(UIAlertAction *_Nonnull ignore) {
                                                           [weakSelf setThreadMutedUntilDate:nil];
                                                       }];
        [actionSheet addAction:action];
    } else {
#ifdef DEBUG
        [actionSheet
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_MINUTE_ACTION",
                                                         @"Label for button to mute a thread for a minute.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_minute")
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
        [actionSheet
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                                                         @"Label for button to mute a thread for a hour.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_hour")
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
        [actionSheet
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                                                         @"Label for button to mute a thread for a day.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_day")
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
        [actionSheet
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                                                         @"Label for button to mute a thread for a week.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_week")
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
        [actionSheet
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_ONE_YEAR_ACTION",
                                                         @"Label for button to mute a thread for a year.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"mute_1_year")
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

    [actionSheet addAction:[OWSAlerts cancelAction]];

    [self presentAlert:actionSheet];
}

- (void)setThreadMutedUntilDate:(nullable NSDate *)value
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [self.thread updateWithMutedUntilDate:value transaction:transaction];
    }];
    
    [self updateTableContents];
}

- (void)copySessionID
{
    UIPasteboard.generalPasteboard.string = self.thread.contactIdentifier;
}

- (void)showMediaGallery
{
    OWSLogDebug(@"");

    MediaGallery *mediaGallery = [[MediaGallery alloc] initWithThread:self.thread
                                                              options:MediaGalleryOptionSliderEnabled];

    self.mediaGallery = mediaGallery;

    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);
    [mediaGallery pushTileViewFromNavController:(OWSNavigationController *)self.navigationController];
}

- (void)tappedConversationSearch
{
    [self.conversationSettingsViewDelegate conversationSettingsDidRequestConversationSearch:self];
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

#ifdef SHOW_COLOR_PICKER

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
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
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

#endif

#pragma mark - OWSSheetViewController

- (void)sheetViewControllerRequestedDismiss:(OWSSheetViewController *)sheetViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
