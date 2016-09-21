//  Created by Michael Kirk on 9/21/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSContactInfoTableViewController.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "OWSAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import "UIUtil.h"
#import <25519/Curve25519.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactInfoTableViewController ()

@property (strong, nonatomic) IBOutlet UITableViewCell *verifyPrivacyCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *toggleDisappearingMessagesCell;
@property (strong, nonatomic) IBOutlet UISwitch *disappearingMessagesSwitch;
@property (strong, nonatomic) IBOutlet UITableViewCell *disappearingMessagesDurationCell;
@property (strong, nonatomic) IBOutlet UILabel *disappearingMessagesDurationLabel;
@property (strong, nonatomic) IBOutlet UISlider *disappearingMessagesDurationSlider;
@property (strong, nonatomic) IBOutlet UIImageView *avatar;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UILabel *signalIdLabel;

@property (nonatomic) TSThread *thread;
@property (nonatomic) NSString *contactName;
@property (nonatomic) NSString *signalId;
@property (nonatomic) UIImage *avatarImage;
@property (nonatomic) BOOL hidePrivacyVerificationCell;

// TODO readonly.
@property (nonatomic) NSArray<NSNumber *> *disappearingMessagesDurations;
@property (nonatomic) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;

@property (nonatomic) TSStorageManager *storageManager;
@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) TSMessagesManager *messagesManager;

@end

typedef enum {
    OWSContactInfoTableCellIndexPrivacyVerification = 0,
    OWSContactInfoTableCellIndexToggleDisappearingMessages = 1,
    OWSContactInfoTableCellIndexConfigureDisappearingMessages = 2
} OWSContactInfoTableCellIndex ;

@implementation OWSContactInfoTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = [TSStorageManager sharedManager];
    _contactsManager = [[Environment getCurrent] contactsManager];
    _messagesManager = [TSMessagesManager sharedManager];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _storageManager = [TSStorageManager sharedManager];
    _contactsManager = [[Environment getCurrent] contactsManager];
    _messagesManager = [TSMessagesManager sharedManager];

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Only show fingerprint for contact threads.
    self.verifyPrivacyCell.hidden = self.hidePrivacyVerificationCell;

    self.nameLabel.text = self.contactName;
    if (self.signalId) {
        self.signalIdLabel.text =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:self.signalId];
    } else {
        // Don't print anything for groups.
        self.signalIdLabel.text = nil;
    }
    self.avatar.image = [OWSAvatarBuilder buildImageForThread:self.thread contactsManager:self.contactsManager];

    self.verifyPrivacyCell.textLabel.text = NSLocalizedString(@"VERIFY_PRIVACY", @"settings table cell label");
    self.toggleDisappearingMessagesCell.textLabel.text
        = NSLocalizedString(@"DISAPPEARING_MESSAGES", @"settings table cell label");

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
                 messagesManager:self.messagesManager];
    }
}

- (void)viewDidLayoutSubviews
{
    // Round avatar corners.
    self.avatar.layer.borderColor = UIColor.clearColor.CGColor;
    self.avatar.layer.masksToBounds = YES;
    self.avatar.layer.cornerRadius = self.avatar.frame.size.height / 2.0f;
}

- (void)configureWithThread:(TSThread *)thread
{
    self.thread = thread;
    self.signalId = thread.contactIdentifier;
    self.contactName = thread.name;

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        if (self.contactName.length == 0) {
            self.contactName = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
        }
        self.hidePrivacyVerificationCell = YES;
    } else {
        self.hidePrivacyVerificationCell = NO;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];
    if (cell.hidden) {
        return 0;
    } else {
        return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    }
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
    self.disappearingMessagesSwitch.on = flag;
    self.disappearingMessagesDurationLabel.enabled = flag;
    self.disappearingMessagesDurationSlider.enabled = flag;
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
            [[OWSFingerprintBuilder alloc] initWithStorageManager:self.storageManager];
        OWSFingerprint *fingerprint = [fingerprintBuilder fingerprintWithTheirSignalId:self.thread.contactIdentifier];

        [controller configureWithThread:self.thread fingerprint:fingerprint contactName:self.contactName];
        controller.dismissDelegate = self;
    }
}

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
    if(cell.selectionStyle == UITableViewCellSelectionStyleNone){
        return nil;
    }
    return indexPath;
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
