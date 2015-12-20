//
//  PrivacySettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"

#import <25519/Curve25519.h>
#import "DJWActionSheet+OWS.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "TSFingerprintGenerator.h"
#import "UIUtil.h"

@interface PrivacySettingsTableViewController ()

@property (nonatomic, strong) UITableViewCell *enableScreenSecurityCell;
@property (nonatomic, strong) UITableViewCell *clearHistoryLogCell;
@property (nonatomic, strong) UITableViewCell *fingerprintCell;
@property (nonatomic, strong) UITableViewCell *shareFingerprintCell;

@property (nonatomic, strong) UISwitch *enableScreenSecuritySwitch;

@property (nonatomic, strong) UILabel *fingerprintLabel;

@property (nonatomic, strong) NSTimer *copiedTimer;

@end

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");

    // Enable Screen Security Cell
    self.enableScreenSecurityCell                = [[UITableViewCell alloc] init];
    self.enableScreenSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"");

    self.enableScreenSecuritySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];

    self.enableScreenSecurityCell.accessoryView          = self.enableScreenSecuritySwitch;
    self.enableScreenSecurityCell.userInteractionEnabled = YES;

    // Clear History Log Cell
    self.clearHistoryLogCell                = [[UITableViewCell alloc] init];
    self.clearHistoryLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"");
    self.clearHistoryLogCell.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;

    // Fingerprint Cell
    self.fingerprintCell =
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Identifier"];
    self.fingerprintCell.textLabel.text            = NSLocalizedString(@"SETTINGS_FINGERPRINT", @"");
    self.fingerprintCell.detailTextLabel.text      = NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY", nil);
    self.fingerprintCell.detailTextLabel.textColor = [UIColor lightGrayColor];

    self.fingerprintLabel               = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 150, 25)];
    self.fingerprintLabel.textColor     = [UIColor lightGrayColor];
    self.fingerprintLabel.font          = [UIFont ows_regularFontWithSize:16.0f];
    self.fingerprintLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.fingerprintCell.accessoryView = self.fingerprintLabel;

    [self setValues];
    [self subsribeToEvents];
}

- (void)subsribeToEvents {
    [self.enableScreenSecuritySwitch addTarget:self
                                        action:@selector(didToggleSwitch:)
                              forControlEvents:UIControlEventTouchUpInside];
}

- (void)setValues {
    [self.enableScreenSecuritySwitch setOn:[Environment.preferences screenSecurityIsEnabled]];
    self.fingerprintLabel.text =
        [TSFingerprintGenerator getFingerprintForDisplay:[[TSStorageManager sharedManager] identityKeyPair].publicKey];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 1;
        case 1:
            return 1;
        case 2:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"SETTINGS_SCREEN_SECURITY_DETAIL", nil);
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return self.enableScreenSecurityCell;
        case 1:
            return self.clearHistoryLogCell;
        case 2:
            switch (indexPath.row) {
                case 0:
                    return self.fingerprintCell;
                case 1:
                    return self.shareFingerprintCell;
            }
    }

    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"");
        case 1:
            return NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"");
        case 2:
            return NSLocalizedString(@"SETTINGS_FINGERPRINT", @"");
        default:
            return nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case 1: {
            [DJWActionSheet showInView:self.parentViewController.view
                             withTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION", @"")
                     cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                destructiveButtonTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON", @"")
                     otherButtonTitles:@[]
                              tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                                if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                    DDLogDebug(@"User Cancelled");
                                } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                                    [[TSStorageManager sharedManager] deleteThreadsAndMessages];
                                } else {
                                    DDLogDebug(@"The user tapped button at index: %li", (long)tappedButtonIndex);
                                }
                              }];

            break;
        }

        case 2:
            switch (indexPath.row) {
                case 0: {
                    // Timer to change label to copied (NSTextAttachment checkmark)
                    if (self.copiedTimer == nil) {
                        self.copiedTimer = [NSTimer scheduledTimerWithTimeInterval:2.0f
                                                                            target:self
                                                                          selector:@selector(endTimer:)
                                                                          userInfo:nil
                                                                           repeats:NO];
                        self.fingerprintCell.detailTextLabel.text =
                            NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY_SUCCESS", @"");
                    } else {
                        self.fingerprintCell.detailTextLabel.text =
                            NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY", nil);
                    }
                    [[UIPasteboard generalPasteboard] setString:self.fingerprintLabel.text];
                    break;
                }

                default:
                    break;
            }
            break;
        default:
            break;
    }
}

#pragma mark - Toggle

- (void)didToggleSwitch:(UISwitch *)sender {
    [Environment.preferences setScreenSecurity:self.enableScreenSecuritySwitch.isOn];
}

#pragma mark - Timer

- (void)endTimer:(id)sender {
    self.fingerprintCell.detailTextLabel.text = NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY", nil);
    [self.copiedTimer invalidate];
    self.copiedTimer = nil;
}

@end
