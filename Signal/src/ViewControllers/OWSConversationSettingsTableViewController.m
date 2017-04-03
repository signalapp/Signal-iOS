//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsTableViewController.h"
#import "BlockListUIUtils.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "NewGroupViewController.h"
#import "OWSAvatarBuilder.h"
#import "OWSBlockingManager.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import "ShowGroupMembersViewController.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
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

static NSString *const OWSConversationSettingsTableViewControllerSegueUpdateGroup =
    @"OWSConversationSettingsTableViewControllerSegueUpdateGroup";
static NSString *const OWSConversationSettingsTableViewControllerSegueShowGroupMembers =
    @"OWSConversationSettingsTableViewControllerSegueShowGroupMembers";

@interface OWSConversationSettingsTableViewController ()

@property (nonatomic) IBOutlet UITableViewCell *verifyPrivacyCell;
@property (nonatomic) IBOutlet UITableViewCell *blocklistStateCell;
@property (nonatomic) IBOutlet UITableViewCell *toggleDisappearingMessagesCell;
@property (nonatomic) IBOutlet UILabel *toggleDisappearingMessagesTitleLabel;
@property (nonatomic) IBOutlet UILabel *toggleDisappearingMessagesDescriptionLabel;
@property (nonatomic) IBOutlet UISwitch *disappearingMessagesSwitch;
@property (nonatomic) IBOutlet UITableViewCell *disappearingMessagesDurationCell;
@property (nonatomic) IBOutlet UILabel *disappearingMessagesDurationLabel;
@property (nonatomic) IBOutlet UISlider *disappearingMessagesDurationSlider;

@property (nonatomic) IBOutlet UIImageView *avatar;
@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UILabel *signalIdLabel;
@property (nonatomic) IBOutletCollection(UIImageView) NSArray *cellIcons;

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
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@end

@implementation OWSConversationSettingsTableViewController

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

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }
    
    [self commonInit];
    
    return self;
}

- (void)commonInit
{
    _storageManager = [TSStorageManager sharedManager];
    _contactsManager = [Environment getCurrent].contactsManager;
    _messageSender = [Environment getCurrent].messageSender;
    _blockingManager = [OWSBlockingManager sharedManager];
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

- (void)loadView
{
    // Initialize with empty contents. We'll populate the
    // contents later.
    self.contents = [OWSTableContents new];

    [super loadView];
}

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
    self.toggleDisappearingMessagesTitleLabel.text
        = NSLocalizedString(@"DISAPPEARING_MESSAGES", @"table cell label in conversation settings");
    self.toggleDisappearingMessagesDescriptionLabel.text
        = NSLocalizedString(@"DISAPPEARING_MESSAGES_DESCRIPTION", @"subheading in conversation settings");

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

    [self updateTableContents];
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    __weak OWSConversationSettingsTableViewController *weakSelf = self;

    NSMutableArray *firstSectionItems = [NSMutableArray new];
    if (!self.isGroupThread && self.thread.hasSafetyNumbers) {
        [firstSectionItems addObject:[OWSTableItem itemWithCustomCellBlock:^{
            weakSelf.verifyPrivacyCell.textLabel.text
                = NSLocalizedString(@"VERIFY_PRIVACY", @"table cell label in conversation settings");
            return weakSelf.verifyPrivacyCell;
        }
                                         actionBlock:^{
                                             [weakSelf
                                                 performSegueWithIdentifier:
                                                     @"OWSConversationSettingsTableViewControllerSegueSafetyNumbers"
                                                                     sender:weakSelf];
                                         }]];
    }

    if (!self.isGroupThread) {
        BOOL isBlocked = [[_blockingManager blockedPhoneNumbers] containsObject:self.signalId];

        [firstSectionItems addObject:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(
                @"CONVERSATION_SETTINGS_BLOCK_THIS_USER", @"table cell label in conversation settings");
            cell.textLabel.textColor = [UIColor blackColor];
            cell.textLabel.font = [UIFont ows_regularFontWithSize:17.f];
            cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            UIImage *icon = [UIImage imageNamed:@"ic_block"];
            OWSAssert(icon);
            cell.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.contentMode = UIViewContentModeScaleToFill;
            cell.imageView.tintColor = [UIColor blackColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISwitch *blockUserSwitch = [UISwitch new];
            blockUserSwitch.on = isBlocked;
            [blockUserSwitch addTarget:self
                                action:@selector(blockUserSwitchDidChange:)
                      forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = blockUserSwitch;
            return cell;
        }
                                                               actionBlock:nil]];
    }

    [firstSectionItems addObject:[OWSTableItem itemWithCustomCellBlock:^{
        weakSelf.toggleDisappearingMessagesCell.selectionStyle = UITableViewCellSelectionStyleNone;
        return weakSelf.toggleDisappearingMessagesCell;
    }
                                                       customRowHeight:108.f
                                                           actionBlock:nil]];

    if (self.disappearingMessagesSwitch.isOn) {
        [firstSectionItems addObject:[OWSTableItem itemWithCustomCellBlock:^{
            weakSelf.disappearingMessagesDurationCell.selectionStyle = UITableViewCellSelectionStyleNone;
            return weakSelf.disappearingMessagesDurationCell;
        }
                                                           customRowHeight:76.f
                                                               actionBlock:nil]];
    }

    [contents addSection:[OWSTableSection sectionWithTitle:nil items:firstSectionItems]];

    if (self.isGroupThread) {
        NSArray *groupItems = @[
            [OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text
                    = NSLocalizedString(@"EDIT_GROUP_ACTION", @"table cell label in conversation settings");
                cell.textLabel.textColor = [UIColor blackColor];
                cell.textLabel.font = [UIFont ows_regularFontWithSize:17.f];
                cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
                actionBlock:^{
                    [weakSelf performSegueWithIdentifier:@"OWSConversationSettingsTableViewControllerSegueUpdateGroup"
                                                  sender:weakSelf];
                }],
            [OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text
                    = NSLocalizedString(@"LEAVE_GROUP_ACTION", @"table cell label in conversation settings");
                cell.textLabel.textColor = [UIColor blackColor];
                cell.textLabel.font = [UIFont ows_regularFontWithSize:17.f];
                cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
                actionBlock:^{
                    [weakSelf didTapLeaveGroup];
                }],
            [OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text
                    = NSLocalizedString(@"LIST_GROUP_MEMBERS_ACTION", @"table cell label in conversation settings");
                cell.textLabel.textColor = [UIColor blackColor];
                cell.textLabel.font = [UIFont ows_regularFontWithSize:17.f];
                cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
                actionBlock:^{
                    [weakSelf
                        performSegueWithIdentifier:@"OWSConversationSettingsTableViewControllerSegueShowGroupMembers"
                                            sender:weakSelf];
                }],
        ];

        [contents addSection:[OWSTableSection sectionWithTitle:NSLocalizedString(@"GROUP_MANAGEMENT_SECTION",
                                                                   @"Conversation settings table section title")
                                                         items:groupItems]];
    }

    self.contents = contents;
    [self.tableView reloadData];
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

    [self updateTableContents];
}

- (void)blockUserSwitchDidChange:(id)sender
{
    OWSAssert(!self.isGroupThread);

    if (![sender isKindOfClass:[UISwitch class]]) {
        DDLogError(@"%@ Unexpected sender for block user switch: %@", self.tag, sender);
    }
    UISwitch *blockUserSwitch = (UISwitch *)sender;

    BOOL isCurrentlyBlocked = [[_blockingManager blockedPhoneNumbers] containsObject:self.signalId];

    if (blockUserSwitch.isOn) {
        OWSAssert(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockPhoneNumberActionSheet:self.thread.contactIdentifier
                                              displayName:self.thread.name
                                       fromViewController:self
                                          blockingManager:_blockingManager
                                          completionBlock:^(BOOL isBlocked) {
                                              // Update switch state if user cancels action.
                                              blockUserSwitch.on = isBlocked;
                                          }];
    } else {
        OWSAssert(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockPhoneNumberActionSheet:self.thread.contactIdentifier
                                                displayName:self.thread.name
                                         fromViewController:self
                                            blockingManager:_blockingManager
                                            completionBlock:^(BOOL isBlocked) {
                                                // Update switch state if user cancels action.
                                                blockUserSwitch.on = isBlocked;
                                            }];
    }
}

- (void)toggleDisappearingMessages:(BOOL)flag
{
    self.disappearingMessagesConfiguration.enabled = flag;

    // When this message is called as a result of the switch being flipped, this will be a no-op
    // but it allows us to resuse the method to set the switch programmatically in view setup.
    self.disappearingMessagesSwitch.on = flag;
    [self durationSliderDidChange:self.disappearingMessagesDurationSlider];
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
