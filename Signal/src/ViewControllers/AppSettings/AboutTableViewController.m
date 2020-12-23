//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "AboutTableViewController.h"
#import "Signal-Swift.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/UIUtil.h>

@import SafariServices;

@implementation AboutTableViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"Navbar title");

    self.useThemeBackgroundColors = YES;

    [self updateTableContents];

    // Crash app if user performs obscure gesture in order to test
    // crash reporting.
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(crashApp)];
    gesture.numberOfTouchesRequired = 2;
    gesture.numberOfTapsRequired = 5;
    [self.tableView addGestureRecognizer:gesture];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pushTokensDidChange:)
                                                 name:[OWSSyncPushTokensJob PushTokensDidChange]
                                               object:nil];
}

- (void)pushTokensDidChange:(NSNotification *)notification
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AboutTableViewController *weakSelf = self;

    OWSTableSection *informationSection = [OWSTableSection new];
    informationSection.headerTitle = NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
    [informationSection addItem:[OWSTableItem labelItemWithText:NSLocalizedString(@"SETTINGS_VERSION", @"")
                                                  accessoryText:AppVersion.shared.currentAppVersionLong]];

    [informationSection
        addItem:[OWSTableItem
                     disclosureItemWithText:NSLocalizedString(@"SETTINGS_LEGAL_TERMS_CELL", @"table cell label")
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"terms")
                                actionBlock:^{
                                    SFSafariViewController *safariVC = [[SFSafariViewController alloc]
                                        initWithURL:[NSURL URLWithString:kLegalTermsUrlString]];
                                    [weakSelf presentViewController:safariVC animated:YES completion:nil];
                                }]];

    [contents addSection:informationSection];

    UILabel *copyrightLabel = [UILabel new];
    copyrightLabel.text = NSLocalizedString(@"SETTINGS_COPYRIGHT", @"");
    copyrightLabel.textColor = Theme.secondaryTextAndIconColor;
    copyrightLabel.font = [UIFont ows_regularFontWithSize:15.0f];
    copyrightLabel.numberOfLines = 2;
    copyrightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    copyrightLabel.textAlignment = NSTextAlignmentCenter;
    informationSection.customFooterView = copyrightLabel;
    informationSection.customFooterHeight = @(60.f);

    if (SSKDebugFlags.verboseAboutView) {
        [self addVerboseContents:contents];
    }

    if (SSKDebugFlags.groupsV2memberStatusIndicators) {
        [self addGroupsV2memberStatusIndicators:contents];
    }

    self.contents = contents;
}

- (void)addVerboseContents:(OWSTableContents *)contents
{
    __block NSUInteger threadCount;
    __block NSUInteger messageCount;
    __block NSUInteger attachmentCount;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadCount = [TSThread anyCountWithTransaction:transaction];
        messageCount = [TSInteraction anyCountWithTransaction:transaction];
        attachmentCount = [TSAttachment anyCountWithTransaction:transaction];
    }];

    NSByteCountFormatter *byteCountFormatter = [NSByteCountFormatter new];

    // format counts with thousands separator
    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    numberFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    OWSTableSection *debugSection = [OWSTableSection new];

    debugSection.headerTitle = @"Debug";

    __weak AboutTableViewController *weakSelf = self;
    [debugSection
        addItem:[OWSTableItem disclosureItemWithText:@"Flags"
                                         actionBlock:^{
                                             UIViewController *flagsViewController = [FlagsViewController new];
                                             [weakSelf.navigationController pushViewController:flagsViewController
                                                                                      animated:YES];
                                         }]];
    [debugSection
        addItem:[OWSTableItem disclosureItemWithText:@"Testing"
                                         actionBlock:^{
                                             UIViewController *testingViewController = [TestingViewController new];
                                             [weakSelf.navigationController pushViewController:testingViewController
                                                                                      animated:YES];
                                         }]];

    TSAccountManager *tsAccountManager = self.tsAccountManager;
    NSString *localNumber = @"Unknown";
    if (tsAccountManager.localNumber != nil) {
        localNumber = tsAccountManager.localNumber;
    }
    [debugSection
        addItem:[OWSTableItem actionItemWithText:[NSString stringWithFormat:@"Local Phone Number: %@", localNumber]
                                     actionBlock:^{
                                         if (tsAccountManager.localNumber != nil) {
                                             UIPasteboard.generalPasteboard.string = tsAccountManager.localNumber;
                                         }
                                     }]];

    NSString *localUuid = @"Unknown";
    if (tsAccountManager.localUuid != nil) {
        localUuid = tsAccountManager.localUuid.UUIDString;
    }
    [debugSection addItem:[OWSTableItem actionItemWithText:[NSString stringWithFormat:@"Local UUID: %@", localUuid]
                                               actionBlock:^{
                                                   if (tsAccountManager.localUuid != nil) {
                                                       UIPasteboard.generalPasteboard.string
                                                           = tsAccountManager.localUuid.UUIDString;
                                                   }
                                               }]];

    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Device ID: %lu",
                                                                    (unsigned long)tsAccountManager.storedDeviceId]]];

    if (tsAccountManager.storedDeviceName != nil) {
        [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Device Name: %@",
                                                                        tsAccountManager.storedDeviceName]]];
    }

    NSString *environmentName = TSConstants.isUsingProductionService ? @"Production" : @"Staging";
    [debugSection
     addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Environment: %@", environmentName]]];

    NSString *formattedThreadCount = [numberFormatter stringFromNumber:@(threadCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Threads: %@", formattedThreadCount]]];

    NSString *formattedMessageCount = [numberFormatter stringFromNumber:@(messageCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Messages: %@", formattedMessageCount]]];

    NSString *formattedAttachmentCount = [numberFormatter stringFromNumber:@(attachmentCount)];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Attachments: %@",
                                                                    formattedAttachmentCount]]];

    NSString *dbSize = [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseFileSize]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database size: %@", dbSize]]];

    NSString *dbWALSize =
        [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseWALFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database WAL size: %@", dbWALSize]]];

    NSString *dbSHMSize =
        [byteCountFormatter stringFromByteCount:(long long)[self.databaseStorage databaseSHMFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database SHM size: %@", dbSHMSize]]];

    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"dataStoreForUI: %@",
                                                          NSStringForDataStore(StorageCoordinator.dataStoreForUI)]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasYdbFile: %d",
                                                                    StorageCoordinator.hasYdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasGrdbFile: %d",
                                                                    StorageCoordinator.hasGrdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"hasUnmigratedYdbFile: %d",
                                                                    StorageCoordinator.hasUnmigratedYdbFile]]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"didEverUseYdb: %d",
                                                                    SSKPreferences.didEverUseYdb]]];

    [contents addSection:debugSection];

    OWSPreferences *preferences = Environment.shared.preferences;
    NSString *_Nullable pushToken = [preferences getPushToken];
    NSString *_Nullable voipToken = [preferences getVoipToken];
    [debugSection
        addItem:[OWSTableItem actionItemWithText:[NSString stringWithFormat:@"Push Token: %@", pushToken ?: @"None"]
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"push_token")
                                     actionBlock:^{
                                         if (pushToken) {
                                             UIPasteboard.generalPasteboard.string = pushToken;
                                         }
                                     }]];
    [debugSection
        addItem:[OWSTableItem actionItemWithText:[NSString stringWithFormat:@"VOIP Token: %@", voipToken ?: @"None"]
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"voip_token")
                                     actionBlock:^{
                                         if (voipToken) {
                                             UIPasteboard.generalPasteboard.string = voipToken;
                                         }
                                     }]];

    // Strip prefix from category, otherwise it's too long to fit into cell on a small device.
    NSString *audioCategory =
        [AVAudioSession.sharedInstance.category stringByReplacingOccurrencesOfString:@"AVAudioSessionCategory"
                                                                          withString:@""];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Audio Category: %@", audioCategory]]];

    NSData *localProfileKey = [self.profileManager localProfileKey].keyData;
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Local Profile Key: %@",
                                                                    localProfileKey.hexadecimalString]]];
}

- (void)addGroupsV2memberStatusIndicators:(OWSTableContents *)contents
{
    SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
    __block BOOL hasGroupsV2Capability;
    __block BOOL hasGroupMigrationCapability;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasGroupsV2Capability = [GroupManager doesUserHaveGroupsV2CapabilityWithAddress:localAddress
                                                                            transaction:transaction];
        hasGroupMigrationCapability = [GroupManager doesUserHaveGroupsV2MigrationCapabilityWithAddress:localAddress
                                                                                           transaction:transaction];
    }];

    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = @"Groups v2";
    [section addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Has Groups v2 capability: %@",
                                                               @(hasGroupsV2Capability)]]];
    [section addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Has Group Migration capability: %@",
                                                               @(hasGroupMigrationCapability)]]];

    [contents addSection:section];
}

- (void)crashApp
{
    OWSFail(@"crashApp");
}

@end
