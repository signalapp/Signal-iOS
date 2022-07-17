//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewController.h"
#import "OWSSoundSettingsViewController.h"
#import "Session-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SignalUtilitiesKit/UIUtil.h>

@import ContactsUI;
@import PromiseKit;

NS_ASSUME_NONNULL_BEGIN

CGFloat kIconViewLength = 24;

@interface OWSConversationSettingsViewController () <OWSSheetViewControllerDelegate>

@property (nonatomic) NSString *threadId;
@property (nonatomic) NSString *threadName;
@property (nonatomic) BOOL isNoteToSelf;
@property (nonatomic) BOOL isClosedGroup;
@property (nonatomic) BOOL isOpenGroup;
@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;

@property (nonatomic) BOOL originalIsDisappearingMessagesEnabled;
@property (nonatomic) NSInteger originalDisappearingMessagesDurationIndex;
@property (nonatomic) BOOL isDisappearingMessagesEnabled;
@property (nonatomic) NSInteger disappearingMessagesDurationIndex;

@property (nonatomic, readonly) UIImageView *avatarView;
@property (nonatomic, readonly) UILabel *disappearingMessagesDurationLabel;
@property (nonatomic) UILabel *displayNameLabel;
@property (nonatomic) SNTextField *displayNameTextField;
@property (nonatomic) UIView *displayNameContainer;
@property (nonatomic) BOOL isEditingDisplayName;

@end

#pragma mark -

@implementation OWSConversationSettingsViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    return self;
}

#pragma mark

- (void)configureWithThreadId:(NSString *)threadId threadName:(NSString *)threadName isClosedGroup:(BOOL)isClosedGroup isOpenGroup:(BOOL)isOpenGroup isNoteToSelf:(BOOL)isNoteToSelf {
    self.threadId = threadId;
    self.threadName = threadName;
    self.isClosedGroup = isClosedGroup;
    self.isOpenGroup = isOpenGroup;
    self.isNoteToSelf = isNoteToSelf;
    
    if (!isClosedGroup && !isOpenGroup) {
        self.threadName = [SMKProfile displayNameWithId:threadId customFallback:@"Anonymous"];
    }
    else {
        self.threadName = threadName;
    }
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

    self.displayNameLabel = [UILabel new];
    self.displayNameLabel.textColor = LKColors.text;
    self.displayNameLabel.font = [UIFont boldSystemFontOfSize:LKValues.largeFontSize];
    self.displayNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.displayNameLabel.textAlignment = NSTextAlignmentCenter;

    self.displayNameTextField = [[SNTextField alloc] initWithPlaceholder:@"Enter a name" usesDefaultHeight:NO];
    self.displayNameTextField.textAlignment = NSTextAlignmentCenter;
    self.displayNameTextField.accessibilityLabel = @"Edit name text field";
    self.displayNameTextField.alpha = 0;

    self.displayNameContainer = [UIView new];
    self.displayNameContainer.accessibilityLabel = @"Edit name text field";
    self.displayNameContainer.isAccessibilityElement = YES;

    [self.displayNameContainer autoSetDimension:ALDimensionHeight toSize:40];
    [self.displayNameContainer addSubview:self.displayNameLabel];
    [self.displayNameLabel autoPinToEdgesOfView:self.displayNameContainer];
    [self.displayNameContainer addSubview:self.displayNameTextField];
    [self.displayNameTextField autoPinToEdgesOfView:self.displayNameContainer];

    if (!self.isClosedGroup && !self.isOpenGroup) {
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showEditNameUI)];
        [self.displayNameContainer addGestureRecognizer:tapGestureRecognizer];
    }

    self.tableView.estimatedRowHeight = 45;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    _disappearingMessagesDurationLabel = [UILabel new];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _disappearingMessagesDurationLabel);

    self.disappearingMessagesDurations = [SMKDisappearingMessagesConfiguration validDurationsSeconds];
    self.isDisappearingMessagesEnabled = [SMKDisappearingMessagesConfiguration isEnabledFor: self.threadId];
    self.disappearingMessagesDurationIndex = [SMKDisappearingMessagesConfiguration durationIndexFor: self.threadId];
    self.originalIsDisappearingMessagesEnabled = self.isDisappearingMessagesEnabled;
    self.originalDisappearingMessagesDurationIndex = self.disappearingMessagesDurationIndex;
    
    [self updateTableContents];

    NSString *title;
    if (!self.isClosedGroup && !self.isOpenGroup) {
        title = NSLocalizedString(@"Settings", @"");
    } else {
        title = NSLocalizedString(@"Group Settings", @"");
    }
    [LKViewControllerUtilities setUpDefaultSessionStyleForVC:self withTitle:title customBackButton:YES];
    self.tableView.backgroundColor = UIColor.clearColor;

    if (!self.isClosedGroup && !self.isOpenGroup) {
        [self updateNavBarButtons];
    }
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    __weak OWSConversationSettingsViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];

    section.customHeaderView = [self mainSectionHeader];
    section.customHeaderHeight = @(UITableViewAutomaticDimension);

    // Copy Session ID
    if (!self.isClosedGroup && !self.isOpenGroup) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                disclosureCellWithName:NSLocalizedString(@"vc_conversation_settings_copy_session_id_button_title", "")
                              iconName:@"ic_copy"
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"copy_session_id")];
        }
        actionBlock:^{
            [weakSelf copySessionID];
        }]];
    }

    // All media
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        return [weakSelf
            disclosureCellWithName:MediaStrings.allMedia
                          iconName:@"actionsheet_camera_roll_black"
           accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"all_media")];
    } actionBlock:^{
        [weakSelf showMediaGallery];
    }]];

    // Invite button
    if (self.isOpenGroup) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                disclosureCellWithName:NSLocalizedString(@"vc_conversation_settings_invite_button_title", "")
                              iconName:@"ic_plus_24"
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"invite")];
        } actionBlock:^{
            [weakSelf inviteUsersToOpenGroup];
        }]];
    }

    // Search
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        NSString *title = NSLocalizedString(@"CONVERSATION_SETTINGS_SEARCH",
            @"Table cell label in conversation settings which returns the user to the "
            @"conversation with 'search mode' activated");
        return [weakSelf
            disclosureCellWithName:title
                          iconName:@"conversation_settings_search"
           accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"search")];
    } actionBlock:^{
        [weakSelf tappedConversationSearch];
    }]];

    // Disappearing messages
    if (![self isOpenGroup] && ![SMKContact isBlockedFor:self.threadId]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [OWSTableItem newCell];
            OWSConversationSettingsViewController *strongSelf = weakSelf;
            OWSCAssertDebug(strongSelf);
            cell.preservesSuperviewLayoutMargins = YES;
            cell.contentView.preservesSuperviewLayoutMargins = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            NSString *iconName
                = (strongSelf.isDisappearingMessagesEnabled ? @"ic_timer" : @"ic_timer_disabled");
            UIImageView *iconView = [strongSelf viewForIconWithName:iconName];

            UILabel *rowLabel = [UILabel new];
            rowLabel.text = NSLocalizedString(
                @"DISAPPEARING_MESSAGES", @"table cell label in conversation settings");
            rowLabel.textColor = LKColors.text;
            rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
            rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

            UISwitch *switchView = [UISwitch new];
            switchView.on = strongSelf.isDisappearingMessagesEnabled;
            [switchView addTarget:strongSelf action:@selector(disappearingMessagesSwitchValueDidChange:)
                forControlEvents:UIControlEventValueChanged];

            UIStackView *topRow =
                [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel, switchView ]];
            topRow.spacing = strongSelf.iconSpacing;
            topRow.alignment = UIStackViewAlignmentCenter;
            [cell.contentView addSubview:topRow];
            [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

            UILabel *subtitleLabel = [UILabel new];
            NSString *displayName;
            if (self.isClosedGroup || self.isOpenGroup) {
                displayName = @"the group";
            } else {
                displayName = [SMKProfile displayNameWithId:self.threadId customFallback:@"anonymous"];
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

            cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"disappearing_messages");

            return cell;
         } customRowHeight:UITableViewAutomaticDimension actionBlock:nil]];

        if (self.isDisappearingMessagesEnabled) {
            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
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
                slider.value = strongSelf.disappearingMessagesDurationIndex;
                [slider addTarget:strongSelf action:@selector(durationSliderDidChange:)
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
            } customRowHeight:UITableViewAutomaticDimension actionBlock:nil]];
        }
    }

    [contents addSection:section];

    // Closed group settings
    __block BOOL isUserMember = NO;
    if (self.isClosedGroup || self.isOpenGroup) {
        isUserMember = [SMKGroupMember isCurrentUserMemberOf:self.threadId];
    }
    if (self.isClosedGroup && isUserMember) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell =
                [weakSelf disclosureCellWithName:NSLocalizedString(@"EDIT_GROUP_ACTION", @"table cell label in conversation settings")
                    iconName:@"table_ic_group_edit"
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"edit_group")];
            cell.userInteractionEnabled = !weakSelf.hasLeftGroup;
            return cell;
        } actionBlock:^{
            [weakSelf editGroup];
        }]];
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell =
                [weakSelf disclosureCellWithName:NSLocalizedString(@"LEAVE_GROUP_ACTION", @"table cell label in conversation settings")
                    iconName:@"table_ic_group_leave"
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"leave_group")];
            cell.userInteractionEnabled = !weakSelf.hasLeftGroup;

            return cell;
        } actionBlock:^{
            [weakSelf didTapLeaveGroup];
        }]];
    }

    if (!self.isNoteToSelf) {
        // Notification sound
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
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

            NSInteger sound = [SMKSound notificationSoundFor:strongSelf.threadId];
            cell.detailTextLabel.text = [SMKSound displayNameFor:sound];

            cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                OWSConversationSettingsViewController, @"notifications");

            return cell;
        }
        customRowHeight:UITableViewAutomaticDimension
        actionBlock:^{
            OWSSoundSettingsViewController *vc = [OWSSoundSettingsViewController new];
            vc.threadId = weakSelf.threadId;
            [weakSelf.navigationController pushViewController:vc animated:YES];
        }]];

        if (self.isClosedGroup || self.isOpenGroup) {
            // Notification Settings
            [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [OWSTableItem newCell];
                OWSConversationSettingsViewController *strongSelf = weakSelf;
                OWSCAssertDebug(strongSelf);
                cell.preservesSuperviewLayoutMargins = YES;
                cell.contentView.preservesSuperviewLayoutMargins = YES;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;

                UIImageView *iconView = [strongSelf viewForIconWithName:@"NotifyMentions"];

                UILabel *rowLabel = [UILabel new];
                rowLabel.text = NSLocalizedString(@"vc_conversation_settings_notify_for_mentions_only_title", @"");
                rowLabel.textColor = LKColors.text;
                rowLabel.font = [UIFont systemFontOfSize:LKValues.mediumFontSize];
                rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

                UISwitch *switchView = [UISwitch new];
                switchView.on = [SMKThread isOnlyNotifyingForMentions:strongSelf.threadId];
                [switchView addTarget:strongSelf action:@selector(notifyForMentionsOnlySwitchValueDidChange:)
                    forControlEvents:UIControlEventValueChanged];

                UIStackView *topRow =
                    [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel, switchView ]];
                topRow.spacing = strongSelf.iconSpacing;
                topRow.alignment = UIStackViewAlignmentCenter;
                [cell.contentView addSubview:topRow];
                [topRow autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeBottom];

                UILabel *subtitleLabel = [UILabel new];
                subtitleLabel.text = NSLocalizedString(@"vc_conversation_settings_notify_for_mentions_only_explanation", @"");
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

                cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"notify_for_mentions_only");

                return cell;
             } customRowHeight:UITableViewAutomaticDimension actionBlock:nil]];
        }

        // Mute thread
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            OWSConversationSettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) { return [UITableViewCell new]; }

            NSString *cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_MUTE_LABEL", @"label for 'mute thread' cell in conversation settings");
            UITableViewCell *cell = [strongSelf disclosureCellWithName:cellTitle iconName:@"Mute"
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"mute")];

            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISwitch *muteConversationSwitch = [UISwitch new];
            NSDate *mutedUntilDate = [SMKThread mutedUntilDateFor:strongSelf.threadId];
            NSDate *now = [NSDate date];
            muteConversationSwitch.on = (mutedUntilDate != nil && [mutedUntilDate timeIntervalSinceDate:now] > 0);
            [muteConversationSwitch addTarget:strongSelf action:@selector(handleMuteSwitchToggled:)
                forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = muteConversationSwitch;

            return cell;
        } actionBlock:nil]];
    }

    // Block contact
    if (!self.isNoteToSelf && !self.isClosedGroup && !self.isOpenGroup) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            OWSConversationSettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) { return [UITableViewCell new]; }

            NSString *cellTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_USER", @"table cell label in conversation settings");
            UITableViewCell *cell = [strongSelf disclosureCellWithName:cellTitle iconName:@"table_ic_block"
                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(OWSConversationSettingsViewController, @"block")];

            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISwitch *blockConversationSwitch = [UISwitch new];
            blockConversationSwitch.on = [SMKContact isBlockedFor:strongSelf.threadId];
            [blockConversationSwitch addTarget:strongSelf action:@selector(blockConversationSwitchDidChange:)
                forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = blockConversationSwitch;

            return cell;
        } actionBlock:nil]];
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

- (void)showProfilePicture:(UITapGestureRecognizer *)tapGesture
{
    LKProfilePictureView *profilePictureView = (LKProfilePictureView *)tapGesture.view;
    UIImage *image = [profilePictureView getProfilePicture];
    if (image == nil) { return; }
    NSString *title = (self.threadName != nil && self.threadName.length > 0) ? self.threadName : @"Anonymous";
    SNProfilePictureVC *profilePictureVC = [[SNProfilePictureVC alloc] initWithImage:image title:title];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:profilePictureVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navController animated:YES completion:nil];
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

    self.displayNameLabel.text = (self.threadName != nil && self.threadName.length > 0) ? self.threadName : @"Anonymous";
    if (!self.isClosedGroup && !self.isOpenGroup) {
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showEditNameUI)];
        [self.displayNameContainer addGestureRecognizer:tapGestureRecognizer];
    }

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ profilePictureView, self.displayNameContainer ]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = LKValues.mediumSpacing;
    stackView.distribution = UIStackViewDistributionEqualCentering;
    stackView.alignment = UIStackViewAlignmentCenter;
    BOOL isSmallScreen = (UIScreen.mainScreen.bounds.size.height - 568) < 1;
    CGFloat horizontalSpacing = isSmallScreen ? LKValues.largeSpacing : LKValues.veryLargeSpacing;
    stackView.layoutMargins = UIEdgeInsetsMake(LKValues.mediumSpacing, horizontalSpacing, LKValues.mediumSpacing, horizontalSpacing);
    [stackView setLayoutMarginsRelativeArrangement:YES];

    if (!self.isClosedGroup && !self.isOpenGroup) {
        SRCopyableLabel *subtitleView = [SRCopyableLabel new];
        subtitleView.textColor = LKColors.text;
        subtitleView.font = [LKFonts spaceMonoOfSize:LKValues.smallFontSize];
        subtitleView.lineBreakMode = NSLineBreakByCharWrapping;
        subtitleView.numberOfLines = 2;
        subtitleView.text = self.threadId;
        subtitleView.textAlignment = NSTextAlignmentCenter;
        [stackView addArrangedSubview:subtitleView];
    }

    [profilePictureView updateForThreadId:self.threadId];

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

    // Do nothing if the values haven't changed (or if it's disabled and only the 'durationIndex'
    // has changed as the 'durationIndex' value defaults to 1 hour when disabled)
    if (
        self.isDisappearingMessagesEnabled == self.originalIsDisappearingMessagesEnabled && (
            !self.originalIsDisappearingMessagesEnabled ||
            self.disappearingMessagesDurationIndex == self.originalDisappearingMessagesDurationIndex
        )
    ) {
        return;
    }
    
    [SMKDisappearingMessagesConfiguration
        update:self.threadId
        isEnabled: self.isDisappearingMessagesEnabled
        durationIndex: self.disappearingMessagesDurationIndex
    ];
}

#pragma mark - Actions

- (void)editGroup
{
    SNEditClosedGroupVC *editClosedGroupVC = [[SNEditClosedGroupVC alloc] initWithThreadId:self.threadId];
    [self.navigationController pushViewController:editClosedGroupVC animated:YES completion:nil];
}

- (void)didTapLeaveGroup
{
    NSString *message;
    if ([SMKGroupMember isCurrentUserAdminOf:self.threadId]) {
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
    if (self.isClosedGroup) {
        return ![SMKGroupMember isCurrentUserMemberOf:self.threadId];
    }

    return NO;
}

- (void)leaveGroup
{
    if (self.isClosedGroup) {
        [[SMKMessageSender leaveClosedGroupWithPublicKey:self.threadId] retainUntilComplete];
    }

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)disappearingMessagesSwitchValueDidChange:(UISwitch *)sender
{
    UISwitch *disappearingMessagesSwitch = (UISwitch *)sender;

    [self toggleDisappearingMessages:disappearingMessagesSwitch.isOn];

    [self updateTableContents];
}

- (void)handleMuteSwitchToggled:(id)sender
{
    UISwitch *uiSwitch = (UISwitch *)sender;
    if (uiSwitch.isOn) {
        [SMKThread updateWithMutedUntilDateTo:[NSDate distantFuture] forThreadId:self.threadId];
    } else {
        [SMKThread updateWithMutedUntilDateTo:nil forThreadId:self.threadId];
    }
}

- (void)blockConversationSwitchDidChange:(id)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        OWSFailDebug(@"Unexpected sender for block user switch: %@", sender);
    }
    if (self.isClosedGroup || self.isOpenGroup) {
        OWSFailDebug(@"unexpected group thread");
    }
    UISwitch *blockConversationSwitch = (UISwitch *)sender;

    BOOL isCurrentlyBlocked = [SMKContact isBlockedFor:self.threadId];

    __weak OWSConversationSettingsViewController *weakSelf = self;
    if (blockConversationSwitch.isOn) {
        OWSAssertDebug(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockThreadActionSheet:self.threadId
                                                from:self
                                     completionBlock:^(BOOL isBlocked) {
                                         // Update switch state if user cancels action.
                                         blockConversationSwitch.on = isBlocked;

                                         // If we successfully blocked then force a config sync
                                         if (isBlocked) {
                                             [SMKMessageSender forceSyncConfigurationNow];
                                         }

                                         [weakSelf updateTableContents];
                                     }];

    } else {
        OWSAssertDebug(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockThreadActionSheet:self.threadId
                                                  from:self
                                       completionBlock:^(BOOL isBlocked) {
                                           // Update switch state if user cancels action.
                                           blockConversationSwitch.on = isBlocked;

                                           // If we successfully unblocked then force a config sync
                                           if (!isBlocked) {
                                               [SMKMessageSender forceSyncConfigurationNow];
                                           }

                                           [weakSelf updateTableContents];
                                       }];
    }
}

- (void)toggleDisappearingMessages:(BOOL)flag
{
    self.isDisappearingMessagesEnabled = flag;

    [self updateTableContents];
}

- (void)durationSliderDidChange:(UISlider *)slider
{
    // snap the slider to a valid value
    NSInteger index = (NSInteger)(slider.value + 0.5);
    [slider setValue:index animated:YES];
    self.disappearingMessagesDurationIndex = index;

    [self updateDisappearingMessagesDurationLabel];
}

- (void)updateDisappearingMessagesDurationLabel
{
    if (self.isDisappearingMessagesEnabled) {
        NSString *keepForFormat = @"Disappear after %@";
        self.disappearingMessagesDurationLabel.text = [NSString
            stringWithFormat:keepForFormat,
            [SMKDisappearingMessagesConfiguration durationStringFor: self.disappearingMessagesDurationIndex]
        ];
    }
    else {
        self.disappearingMessagesDurationLabel.text
            = NSLocalizedString(@"KEEP_MESSAGES_FOREVER", @"Slider label when disappearing messages is off");
    }

    [self.disappearingMessagesDurationLabel setNeedsLayout];
    [self.disappearingMessagesDurationLabel.superview setNeedsLayout];
}

- (void)copySessionID
{
    UIPasteboard.generalPasteboard.string = self.threadId;
}

- (void)inviteUsersToOpenGroup
{
    NSString *threadId = self.threadId;
    SNUserSelectionVC *userSelectionVC = [[SNUserSelectionVC alloc] initWithTitle:NSLocalizedString(@"vc_conversation_settings_invite_button_title", @"")
                                                                        excluding:[NSSet new]
                                                                       completion:^(NSSet<NSString *> *selectedUsers) {
        [SMKOpenGroup inviteUsers:selectedUsers toOpenGroupFor:threadId];
    }];
    [self.navigationController pushViewController:userSelectionVC animated:YES];
}

- (void)showMediaGallery
{
    OWSLogDebug(@"");

    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);
    [SNMediaGallery pushTileViewWithSliderEnabledForThreadId:self.threadId isClosedGroup:self.isClosedGroup isOpenGroup:self.isOpenGroup fromNavController:(OWSNavigationController *)self.navigationController];
}

- (void)tappedConversationSearch
{
    [self.conversationSettingsViewDelegate conversationSettingsDidRequestConversationSearch:self];
}

- (void)notifyForMentionsOnlySwitchValueDidChange:(id)sender
{
    UISwitch *uiSwitch = (UISwitch *)sender;
    BOOL isEnabled = uiSwitch.isOn;
    
    [SMKThread setIsOnlyNotifyingForMentions:self.threadId to:isEnabled];
}

- (void)hideEditNameUI
{
    self.isEditingDisplayName = NO;
}

- (void)showEditNameUI
{
    self.isEditingDisplayName = YES;
}

- (void)setIsEditingDisplayName:(BOOL)isEditingDisplayName
{
    _isEditingDisplayName = isEditingDisplayName;

    [self updateNavBarButtons];

    [UIView animateWithDuration:0.25 animations:^{
        self.displayNameLabel.alpha = self.isEditingDisplayName ? 0 : 1;
        self.displayNameTextField.alpha = self.isEditingDisplayName ? 1 : 0;
    }];
    if (self.isEditingDisplayName) {
        [self.displayNameTextField becomeFirstResponder];
    } else {
        [self.displayNameTextField resignFirstResponder];
    }
}

- (void)saveName
{
    if (self.isClosedGroup || self.isOpenGroup) { return; }
    
    NSString *text = [self.displayNameTextField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.displayNameLabel.text = [SMKProfile displayNameAfterSavingNickname:text forProfileId:self.threadId];
    [self hideEditNameUI];
}

- (void)updateNavBarButtons
{
    if (self.isEditingDisplayName) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(hideEditNameUI)];
        cancelButton.tintColor = LKColors.text;
        cancelButton.accessibilityLabel = @"Cancel button";
        cancelButton.isAccessibilityElement = YES;
        self.navigationItem.leftBarButtonItem = cancelButton;
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(saveName)];
        doneButton.tintColor = LKColors.text;
        doneButton.accessibilityLabel = @"Done button";
        doneButton.isAccessibilityElement = YES;
        self.navigationItem.rightBarButtonItem = doneButton;
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(showEditNameUI)];
        editButton.tintColor = LKColors.text;
        editButton.accessibilityLabel = @"Done button";
        editButton.isAccessibilityElement = YES;
        self.navigationItem.rightBarButtonItem = editButton;
    }
}

#pragma mark - Notifications

// FIXME: When this screen gets refactored, make sure to observe changes for relevant profile image updates
- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    NSString *recipientId = @"";//notification.userInfo[NSNotification.profileRecipientIdKey];
    OWSAssertDebug(recipientId.length > 0);

    if (recipientId.length > 0 && !self.isClosedGroup && !self.isOpenGroup && self.threadId == recipientId) {
        DispatchMainThreadSafe(^{
            [self updateTableContents];
        });
    }
}

#pragma mark - OWSSheetViewController

- (void)sheetViewControllerRequestedDismiss:(OWSSheetViewController *)sheetViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
