//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AboutTableViewController.h"
#import "Signal-Swift.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSDatabaseView.h>

@implementation AboutTableViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"Navbar title");

    [self updateTableContents];

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

    OWSTableSection *informationSection = [OWSTableSection new];
    informationSection.headerTitle = NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
    [informationSection addItem:[OWSTableItem labelItemWithText:NSLocalizedString(@"SETTINGS_VERSION", @"")
                                                  accessoryText:[[[NSBundle mainBundle] infoDictionary]
                                                                    objectForKey:@"CFBundleVersion"]]];

    [informationSection addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_LEGAL_TERMS_CELL",
                                                                         @"table cell label")
                                                         actionBlock:^{
                                                             [[UIApplication sharedApplication]
                                                                 openURL:[NSURL URLWithString:kLegalTermsUrlString]];
                                                         }]];
    [contents addSection:informationSection];

    OWSTableSection *helpSection = [OWSTableSection new];
    helpSection.headerTitle = NSLocalizedString(@"SETTINGS_HELP_HEADER", @"");
    [helpSection addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_SUPPORT", @"")
                                                  actionBlock:^{
                                                      [[UIApplication sharedApplication]
                                                          openURL:[NSURL URLWithString:@"https://support.signal.org"]];
                                                  }]];
    [contents addSection:helpSection];

    UILabel *copyrightLabel = [UILabel new];
    copyrightLabel.text = NSLocalizedString(@"SETTINGS_COPYRIGHT", @"");
    copyrightLabel.textColor = [UIColor ows_darkGrayColor];
    copyrightLabel.font = [UIFont ows_regularFontWithSize:15.0f];
    copyrightLabel.numberOfLines = 2;
    copyrightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    copyrightLabel.textAlignment = NSTextAlignmentCenter;
    helpSection.customFooterView = copyrightLabel;
    helpSection.customFooterHeight = @(60.f);

#ifdef DEBUG
    __block NSUInteger threadCount;
    __block NSUInteger messageCount;
    __block NSUInteger attachmentCount;
    [OWSPrimaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        threadCount = [transaction numberOfKeysInCollection:[TSThread collection]];
        messageCount = [transaction numberOfKeysInCollection:[TSInteraction collection]];
        attachmentCount = [transaction numberOfKeysInCollection:[TSAttachment collection]];
    }];

    NSByteCountFormatter *byteCountFormatter = [NSByteCountFormatter new];

    // format counts with thousands separator
    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    numberFormatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    OWSTableSection *debugSection = [OWSTableSection new];

    debugSection.headerTitle = @"Debug";

    NSString *formattedThreadCount = [numberFormatter stringFromNumber:@(threadCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Threads: %@", formattedThreadCount]]];

    NSString *formattedMessageCount = [numberFormatter stringFromNumber:@(messageCount)];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Messages: %@", formattedMessageCount]]];

    NSString *formattedAttachmentCount = [numberFormatter stringFromNumber:@(attachmentCount)];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Attachments: %@",
                                                                    formattedAttachmentCount]]];

    NSString *dbSize =
        [byteCountFormatter stringFromByteCount:(long long)[OWSPrimaryStorage.sharedManager databaseFileSize]];
    [debugSection addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database size: %@", dbSize]]];

    NSString *dbWALSize =
        [byteCountFormatter stringFromByteCount:(long long)[OWSPrimaryStorage.sharedManager databaseWALFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database WAL size: %@", dbWALSize]]];

    NSString *dbSHMSize =
        [byteCountFormatter stringFromByteCount:(long long)[OWSPrimaryStorage.sharedManager databaseSHMFileSize]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Database SHM size: %@", dbSHMSize]]];

    [contents addSection:debugSection];

    OWSPreferences *preferences = [Environment preferences];
    NSString *_Nullable pushToken = [preferences getPushToken];
    NSString *_Nullable voipToken = [preferences getVoipToken];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Push Token: %@", pushToken ?: @"None"]]];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"VOIP Token: %@", voipToken ?: @"None"]]];

    // Strip prefix from category, otherwise it's too long to fit into cell on a small device.
    NSString *audioCategory =
        [AVAudioSession.sharedInstance.category stringByReplacingOccurrencesOfString:@"AVAudioSessionCategory"
                                                                          withString:@""];
    [debugSection
        addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Audio Category: %@", audioCategory]]];
#endif

    self.contents = contents;
}

@end
