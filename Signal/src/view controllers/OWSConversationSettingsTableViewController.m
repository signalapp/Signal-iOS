//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsTableViewController.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "NewGroupViewController.h"
#import "OWSAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import "ShowGroupMembersViewController.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIViewController+OWS.h"
#import <25519/Curve25519.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSConversationSettingsTableViewControllerSection) {
    OWSConversationSettingsTableViewControllerSectionContact,
    OWSConversationSettingsTableViewControllerSectionGroup
};

typedef NS_ENUM(NSUInteger, OWSConversationSettingsTableViewControllerContactCellIndex) {
    OWSConversationSettingsTableViewControllerCellIndexShowFingerprint,
    OWSConversationSettingsTableViewControllerCellIndexToggleDisappearingMessages,
    OWSConversationSettingsTableViewControllerCellIndexSetDisappearingMessagesDuration
};

typedef NS_ENUM(NSUInteger, OWSConversationSettingsTableViewControllerGroupCellIndex) {
    OWSConversationSettingsTableViewControllerCellIndexUpdateGroup,
    OWSConversationSettingsTableViewControllerCellIndexLeaveGroup,
    OWSConversationSettingsTableViewControllerCellIndexSeeGroupMembers
};

static NSString *const OWSConversationSettingsTableViewControllerSegueUpdateGroup =
    @"OWSConversationSettingsTableViewControllerSegueUpdateGroup";
static NSString *const OWSConversationSettingsTableViewControllerSegueShowGroupMembers =
    @"OWSConversationSettingsTableViewControllerSegueShowGroupMembers";

@interface OWSConversationSettingsTableViewController ()

@property (strong, nonatomic) IBOutlet UITableViewCell *verifyPrivacyCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *toggleDisappearingMessagesCell;
@property (strong, nonatomic) IBOutlet UILabel *toggleDisappearingMessagesTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *toggleDisappearingMessagesDescriptionLabel;
@property (strong, nonatomic) IBOutlet UISwitch *disappearingMessagesSwitch;
@property (strong, nonatomic) IBOutlet UITableViewCell *disappearingMessagesDurationCell;
@property (strong, nonatomic) IBOutlet UILabel *disappearingMessagesDurationLabel;
@property (strong, nonatomic) IBOutlet UISlider *disappearingMessagesDurationSlider;

@property (strong, nonatomic) IBOutlet UITableViewCell *updateGroupCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *leaveGroupCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *listGroupMembersCell;
@property (strong, nonatomic) IBOutlet UIImageView *avatar;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UILabel *signalIdLabel;
@property (strong, nonatomic) IBOutletCollection(UIImageView) NSArray *cellIcons;

@property (nonatomic) TSThread *thread;
@property (nonatomic) NSString *contactName;
@property (nonatomic) NSString *signalId;
@property (nonatomic) UIImage *avatarImage;
@property (nonatomic) BOOL isGroupThread;

@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;
@property (nonatomic) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

@end

@implementation OWSConversationSettingsTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = [TSStorageManager sharedManager];
    _contactsManager = [Environment getCurrent].contactsManager;
    _messageSender = [[OWSMessageSender alloc] initWithNetworkManager:[Environment getCurrent].networkManager
                                                       storageManager:_storageManager
                                                      contactsManager:_contactsManager
                                                      contactsUpdater:[Environment getCurrent].contactsUpdater];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _storageManager = [TSStorageManager sharedManager];
    _contactsManager = [Environment getCurrent].contactsManager;
    _messageSender = [[OWSMessageSender alloc] initWithNetworkManager:[Environment getCurrent].networkManager
                                                       storageManager:_storageManager
                                                      contactsManager:_contactsManager
                                                      contactsUpdater:[Environment getCurrent].contactsUpdater];

    return self;
}

- (void)configureWithThread:(TSThread *)thread
{
    self.thread = thread;
    self.signalId = thread.contactIdentifier;
    self.contactName = thread.name;

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        self.isGroupThread = YES;
        if (self.contactName.length == 0) {
            self.contactName = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
        }
    } else {
        self.isGroupThread = NO;
    }
}

#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.nameLabel.text = self.contactName;
    if (self.signalId) {
        self.signalIdLabel.text =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:self.signalId];
    } else {
        // Don't print anything for groups.
        self.signalIdLabel.text = nil;
    }
    self.avatar.image = [OWSAvatarBuilder buildImageForThread:self.thread contactsManager:self.contactsManager];
    self.nameLabel.font = [UIFont ows_dynamicTypeTitle2Font];

    // Translations
    self.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");
    self.verifyPrivacyCell.textLabel.text
        = NSLocalizedString(@"VERIFY_PRIVACY", @"table cell label in conversation settings");
    self.toggleDisappearingMessagesTitleLabel.text
        = NSLocalizedString(@"DISAPPEARING_MESSAGES", @"table cell label in conversation settings");
    self.toggleDisappearingMessagesDescriptionLabel.text
        = NSLocalizedString(@"DISAPPEARING_MESSAGES_DESCRIPTION", @"subheading in conversation settings");
    self.updateGroupCell.textLabel.text
        = NSLocalizedString(@"EDIT_GROUP_ACTION", @"table cell label in conversation settings");
    self.leaveGroupCell.textLabel.text
        = NSLocalizedString(@"LEAVE_GROUP_ACTION", @"table cell label in conversation settings");
    self.listGroupMembersCell.textLabel.text
        = NSLocalizedString(@"LIST_GROUP_MEMBERS_ACTION", @"table cell label in conversation settings");

    [self useOWSBackButton];

    self.toggleDisappearingMessagesCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.disappearingMessagesDurationCell.selectionStyle = UITableViewCellSelectionStyleNone;

    self.disappearingMessagesDurations = [OWSDisappearingMessagesConfiguration validDurationsSeconds];
    self.disappearingMessagesDurationSlider.maximumValue = (float)(self.disappearingMessagesDurations.count - 1);
    self.disappearingMessagesDurationSlider.minimumValue = 0;
    self.disappearingMessagesDurationSlider.continuous = YES; // NO fires change event only once you let go

    self.disappearingMessagesConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];

    if (!self.disappearingMessagesConfiguration) {
        self.disappearingMessagesConfiguration =
            [[OWSDisappearingMessagesConfiguration alloc] initDefaultWithThreadId:self.thread.uniqueId];
    }

    self.disappearingMessagesDurationSlider.value = self.disappearingMessagesConfiguration.durationIndex;
    [self toggleDisappearingMessages:self.disappearingMessagesConfiguration.isEnabled];

    // RADAR http://www.openradar.me/23759908
    // Finding that occasionally the tabel icons are not being tinted
    // i.e. rendered as white making them invisible.
    for (UIImageView *cellIcon in self.cellIcons) {
        [cellIcon tintColorDidChange];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // HACK to unselect rows when swiping back
    // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:animated];
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
                    configuration:self.disappearingMessagesConfiguration];
        [infoMessage save];

        [OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob
            runWithConfiguration:self.disappearingMessagesConfiguration
                          thread:self.thread
                   messageSender:self.messageSender];
    }
}

- (void)viewDidLayoutSubviews
{
    // Round avatar corners.
    self.avatar.layer.borderColor = UIColor.clearColor.CGColor;
    self.avatar.layer.masksToBounds = YES;
    self.avatar.layer.cornerRadius = self.avatar.frame.size.height / 2.0f;
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger baseCount = [super tableView:tableView numberOfRowsInSection:section];

    if (section == OWSConversationSettingsTableViewControllerSectionGroup) {
        if (self.isGroupThread) {
            return baseCount;
        } else {
            return 0;
        }
    }

    if (section == OWSConversationSettingsTableViewControllerSectionContact) {
        if (!self.thread.hasSafetyNumbers) {
            baseCount -= 1;
        }

        if (!self.disappearingMessagesSwitch.isOn) {
            // hide duration slider when disappearing messages is off.
            baseCount -= 1;
        }
    }
    return baseCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if (indexPath.section == OWSConversationSettingsTableViewControllerSectionContact
        && !self.thread.hasSafetyNumbers) {

        // Since fingerprint cell is hidden for some threads we offset our index path
        NSIndexPath *offsetIndexPath = [NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section];
        return [super tableView:tableView cellForRowAtIndexPath:offsetIndexPath];
    }

    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];

    // group vs. contact thread have some cells slider at different index.
    if (cell == self.disappearingMessagesDurationCell) {
        NSIndexPath *originalIndexPath = [NSIndexPath
            indexPathForRow:OWSConversationSettingsTableViewControllerCellIndexSetDisappearingMessagesDuration
                  inSection:OWSConversationSettingsTableViewControllerSectionContact];

        return [super tableView:tableView heightForRowAtIndexPath:originalIndexPath];
    }
    if (cell == self.toggleDisappearingMessagesCell) {
        NSIndexPath *originalIndexPath =
            [NSIndexPath indexPathForRow:OWSConversationSettingsTableViewControllerCellIndexToggleDisappearingMessages
                               inSection:OWSConversationSettingsTableViewControllerSectionContact];

        return [super tableView:tableView heightForRowAtIndexPath:originalIndexPath];
    } else {
        return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    }
}

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    // Don't highlight rows that have no selection style.
    if (cell.selectionStyle == UITableViewCellSelectionStyleNone) {
        return nil;
    }
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogDebug(@"%@ tapped indexPath:%@", self.tag, indexPath);

    if (indexPath.section == OWSConversationSettingsTableViewControllerSectionGroup
        && indexPath.row == OWSConversationSettingsTableViewControllerCellIndexLeaveGroup) {

        [self didTapLeaveGroup];
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == OWSConversationSettingsTableViewControllerSectionGroup) {
        if (self.isGroupThread) {
            return NSLocalizedString(@"GROUP_MANAGEMENT_SECTION", @"Conversation settings table section title");
        } else {
            return nil;
        }
    } else {
        return [super tableView:tableView titleForHeaderInSection:section];
    }
}

#pragma mark - Actions

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

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                  style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *_Nonnull action) {
                    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
                }];
    [alertController addAction:cancelAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)leaveGroup
{
    TSGroupThread *gThread = (TSGroupThread *)self.thread;
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                     inThread:gThread
                                                                  messageBody:@""];
    message.groupMetaMessage = TSGroupMessageQuit;
    [self.messageSender sendMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully left group.", self.tag);
        }
        failure:^(NSError *error) {
            DDLogWarn(@"%@ Failed to leave group with error: %@", self.tag, error);
        }];

    NSMutableArray *newGroupMemberIds = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
    [newGroupMemberIds removeObject:[self.storageManager localNumber]];
    gThread.groupModel.groupMemberIds = newGroupMemberIds;
    [gThread save];

    [self.navigationController popViewControllerAnimated:YES];
}

- (void)presentedModalWasDismissed
{
    // Else row stays selected after dismissing modal.
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

- (IBAction)disappearingMessagesSwitchValueDidChange:(id)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        DDLogError(@"%@ Unexpected sender for disappearing messages switch: %@", self.tag, sender);
    }
    UISwitch *disappearingMessagesSwitch = (UISwitch *)sender;
    [self toggleDisappearingMessages:disappearingMessagesSwitch.isOn];
}

- (void)toggleDisappearingMessages:(BOOL)flag
{
    self.disappearingMessagesConfiguration.enabled = flag;

    // When this message is called as a result of the switch being flipped, this will be a no-op
    // but it allows us to resuse the method to set the switch programmatically in view setup.
    self.disappearingMessagesSwitch.on = flag;
    [self durationSliderDidChange:self.disappearingMessagesDurationSlider];

    // Animate show/hide of duration settings.
    if (flag) {
        [self.tableView insertRowsAtIndexPaths:@[ self.indexPathForDurationSlider ]
                              withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:@[ self.indexPathForDurationSlider ]
                              withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (NSIndexPath *)indexPathForDurationSlider
{
    if (!self.thread.hasSafetyNumbers) {
        return [NSIndexPath
            indexPathForRow:OWSConversationSettingsTableViewControllerCellIndexSetDisappearingMessagesDuration - 1
                  inSection:OWSConversationSettingsTableViewControllerSectionContact];
    } else {
        return [NSIndexPath
            indexPathForRow:OWSConversationSettingsTableViewControllerCellIndexSetDisappearingMessagesDuration
                  inSection:OWSConversationSettingsTableViewControllerSectionContact];
    }
}

- (IBAction)durationSliderDidChange:(UISlider *)slider
{
    // snap the slider to a valid value
    NSUInteger index = (NSUInteger)(slider.value + 0.5);
    [slider setValue:index animated:YES];
    NSNumber *numberOfSeconds = self.disappearingMessagesDurations[index];
    self.disappearingMessagesConfiguration.durationSeconds = [numberOfSeconds unsignedIntValue];

    if (self.disappearingMessagesConfiguration.isEnabled) {
        NSString *keepForFormat = NSLocalizedString(@"KEEP_MESSAGES_DURATION",
            @"Slider label embeds {{TIME_AMOUNT}}, e.g. '2 hours'. See *_TIME_AMOUNT strings for examples.");
        self.disappearingMessagesDurationLabel.text =
            [NSString stringWithFormat:keepForFormat, self.disappearingMessagesConfiguration.durationString];
    } else {
        self.disappearingMessagesDurationLabel.text
            = NSLocalizedString(@"KEEP_MESSAGES_FOREVER", @"Slider label when disappearing messages is off");
    }
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    if ([segue.destinationViewController isKindOfClass:[FingerprintViewController class]]) {
        FingerprintViewController *controller = (FingerprintViewController *)segue.destinationViewController;

        OWSFingerprintBuilder *fingerprintBuilder =
            [[OWSFingerprintBuilder alloc] initWithStorageManager:self.storageManager
                                                  contactsManager:self.contactsManager];

        OWSFingerprint *fingerprint = [fingerprintBuilder fingerprintWithTheirSignalId:self.thread.contactIdentifier];

        [controller configureWithThread:self.thread fingerprint:fingerprint contactName:self.contactName];
        controller.dismissDelegate = self;
    } else if ([segue.identifier isEqualToString:OWSConversationSettingsTableViewControllerSegueUpdateGroup]) {
        NewGroupViewController *vc = [segue destinationViewController];
        [vc configWithThread:(TSGroupThread *)self.thread];
    } else if ([segue.identifier isEqualToString:OWSConversationSettingsTableViewControllerSegueShowGroupMembers]) {
        ShowGroupMembersViewController *vc = [segue destinationViewController];
        [vc configWithThread:(TSGroupThread *)self.thread];
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
