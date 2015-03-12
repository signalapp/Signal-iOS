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
#import "TouchIDHelper.h"
#import "TSFingerprintGenerator.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "UIUtil.h"

typedef NS_ENUM(NSInteger, TSSettingsSections) {
    TSSettingsSecuritySection,
    TSSettingsHistorySection,
    TSSettingsFingerprintSection,
    
    TSSettingsSectionCount
};

@interface PrivacySettingsTableViewController () {
    BOOL touchIDAvailable;
}

@property (nonatomic, strong) UITableViewCell * enableScreenSecurityCell;
@property (nonatomic, strong) UITableViewCell * enableTouchIDSecurityCell;

@property (nonatomic, strong) UITableViewCell * clearHistoryLogCell;
@property (nonatomic, strong) UITableViewCell * fingerprintCell;
@property (nonatomic, strong) UITableViewCell * shareFingerprintCell;

@property (nonatomic, strong) UISwitch * enableScreenSecuritySwitch;
@property (nonatomic, strong) UISwitch * enableTouchIDSecuritySwitch;

@property (nonatomic, strong) UILabel * fingerprintLabel;

@property (nonatomic, strong) NSTimer * copiedTimer;

@end

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

-(instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

-(void)loadView
{
    [super loadView];
    
    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");
    
    //Enable Screen Security Cell
    self.enableScreenSecurityCell = [[UITableViewCell alloc]init];
    self.enableScreenSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"");
    
    self.enableScreenSecuritySwitch = [[UISwitch alloc]initWithFrame:CGRectZero];
    
    self.enableScreenSecurityCell.accessoryView = self.enableScreenSecuritySwitch;
    self.enableScreenSecurityCell.userInteractionEnabled = YES;
    
    self.enableTouchIDSecurityCell = [[UITableViewCell alloc] initWithStyle: UITableViewCellStyleSubtitle reuseIdentifier:@"touchid"];
    self.enableTouchIDSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_TOUCHID_SECURITY", @"");
    self.enableTouchIDSecurityCell.detailTextLabel.text = NSLocalizedString(@"SETTINGS_TOUCHID_SECURITY_MORE", @"");
    
    self.enableTouchIDSecuritySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enableScreenSecuritySwitch.enabled = NO; // Disable until we verify
    
    self.enableTouchIDSecurityCell.accessoryView = self.enableTouchIDSecuritySwitch;
    self.enableTouchIDSecurityCell.userInteractionEnabled = YES;
    
    
    //Clear History Log Cell
    self.clearHistoryLogCell = [[UITableViewCell alloc]init];
    self.clearHistoryLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"");
    self.clearHistoryLogCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    //Fingerprint Cell
    self.fingerprintCell = [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Identifier"];
    self.fingerprintCell.textLabel.text = NSLocalizedString(@"SETTINGS_FINGERPRINT", @"");
    self.fingerprintCell.detailTextLabel.text = NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY",nil);
    self.fingerprintCell.detailTextLabel.textColor = [UIColor lightGrayColor];
    
    self.fingerprintLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, 150, 25)];
    self.fingerprintLabel.textColor = [UIColor lightGrayColor];
    self.fingerprintLabel.font = [UIFont ows_regularFontWithSize:16.0f]; 
    self.fingerprintLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    
    self.fingerprintCell.accessoryView = self.fingerprintLabel;
    
    [self setValues];
    [self subscribeToEvents];

}

-(void)subscribeToEvents
{
    [self.enableScreenSecuritySwitch addTarget:self action:@selector(didToggleSwitch:) forControlEvents:UIControlEventTouchUpInside];
    [self.enableTouchIDSecuritySwitch addTarget:self action:@selector(didToggleSwitch:) forControlEvents:UIControlEventTouchUpInside];
}

-(void)setValues
{
    [self detectTouchID];
    [self validateSwitches];
    self.fingerprintLabel.text = [TSFingerprintGenerator getFingerprintForDisplay:[[TSStorageManager sharedManager]identityKeyPair].publicKey];
}
-(void)detectTouchID {
    if (TouchIDHelper.touchIDAvailable) {
        touchIDAvailable = YES;
        DDLogCDebug(@"TouchID is available");
        self.enableTouchIDSecuritySwitch.enabled = YES;
    } else {
        // Cannot use touchID at this time / on this device
        DDLogCDebug(@"TouchID is not available at this time.");
    }
    
#if DEBUG
    // Always Show TouchID controls for debugging!
    touchIDAvailable = YES;
    self.enableTouchIDSecuritySwitch.enabled = YES;
#endif
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return TSSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case TSSettingsSecuritySection: {
            if (touchIDAvailable) {
                return 2;
            } else {
                return 1;
            }
        }
        case TSSettingsHistorySection: return 1;
        case TSSettingsFingerprintSection: return 1;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    switch (indexPath.section) {
        case TSSettingsSecuritySection: {
            switch (indexPath.row) {
                case 0: return self.enableScreenSecurityCell;
                case 1: return self.enableTouchIDSecurityCell;
            }
        }
        case TSSettingsHistorySection: return self.clearHistoryLogCell;
        case TSSettingsFingerprintSection:
            switch (indexPath.row) {
                case 0: return self.fingerprintCell;
                case 1: return self.shareFingerprintCell;
            }
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case TSSettingsSecuritySection: return NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"");
        case TSSettingsHistorySection: return NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"");
        case TSSettingsFingerprintSection: return NSLocalizedString(@"SETTINGS_FINGERPRINT_TITLE", @"");
        default: return nil;
    }
}

-(BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (
        touchIDAvailable
        && indexPath.section == TSSettingsSecuritySection && indexPath.row == 0
        && Environment.preferences.screenSecurityIsEnabled
        && Environment.preferences.touchIDSecurityIsEnabled
        ) {
        // Warn the user tapping on the *disabled* screen security switch that they need to disable touchID first.
        // Since this is a security-lowering operation, don't offer them an automatic button to do this.
        
        UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"SETTINGS_DISABLE_SCREEN_SECURITY_WARNING_TOUCHID_TITLE", @"")
                                                         message:NSLocalizedString(@"SETTINGS_DISABLE_SCREEN_SECURITY_WARNING_TOUCHID_MESSAGE", @"")
                                                        delegate:nil
                                               cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                               otherButtonTitles:nil];
        [alert show];
    }
    return YES;
}
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case TSSettingsHistorySection:
        {
            [DJWActionSheet showInView:self.parentViewController.view
                             withTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION", @"")
                     cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                destructiveButtonTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON", @"")
                     otherButtonTitles:@[]
                              tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                  [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                                  if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                      DDLogCDebug(@"User Cancelled");
                                      
                                  } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex){
                                      [[TSStorageManager sharedManager] deleteThreadsAndMessages];
                                  } else {
                                      DDLogCDebug(@"The user tapped button at index: %li", (long)tappedButtonIndex);
                                  }
                              }];

            break;
        }
        
        case TSSettingsFingerprintSection:
            switch (indexPath.row) {
                case 0:
                {
                    //Timer to change label to copied (NSTextAttachment checkmark)
                    if (self.copiedTimer == nil) {
                        self.copiedTimer = [NSTimer scheduledTimerWithTimeInterval:2.0f target:self selector:@selector(endTimer:) userInfo:nil repeats:NO];
                        self.fingerprintCell.detailTextLabel.text = NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY_SUCCESS", @"");
                    } else {
                        self.fingerprintCell.detailTextLabel.text = NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY",nil);
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

-(void)didToggleSwitch:(UISwitch*)sender
{
    BOOL on = sender.isOn;
    
    if (sender == self.enableScreenSecuritySwitch) {
        Environment.preferences.screenSecurity = on;
    } else if (sender == self.enableTouchIDSecuritySwitch) {
        Environment.preferences.touchIDSecurity = on;
        
        if (on && !Environment.preferences.screenSecurityIsEnabled) {
            [DJWActionSheet showInView:self.parentViewController.view
                             withTitle:NSLocalizedString(@"SETTINGS_CONFIRM_ENABLE_SCREEN_SECURITY_TITLE", @"")
                     cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                destructiveButtonTitle:nil
                     otherButtonTitles:@[NSLocalizedString(@"TXT_ENABLE_TITLE", @"")]
                              tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                  if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                      DDLogCDebug(@"User Cancelled");
                                      
                                      Environment.preferences.touchIDSecurity = NO;
                                      [self.enableTouchIDSecuritySwitch setOn:NO animated:YES];
                                  } else {
                                      DDLogCDebug(@"The user enabled TouchID Security");
                                      Environment.preferences.screenSecurity = YES;
                                      [self validateSwitches];
                                  }
                              }];
        } else if (!on) {
            // To disable TouchID we should make sure the owner of the device is the one doing so.
            // Let's be more flexible however, if touchID is unavailable (say due to hardware flaw), we should still allow disabling.
            
            __weak typeof(self) weakSelf = self;
            [TouchIDHelper authenticateViaPasswordOrTouchIDCompletion:^(TSTouchIDAuthResult result) {
                if (result == TSTouchIDAuthResultFailed) {
                    // 1. restore preference state
                    Environment.preferences.touchIDSecurity = NO;
                    // 2. revalidate switches
                    PrivacySettingsTableViewController * strongSelf = weakSelf;
                    [strongSelf validateSwitches];
                }
            }];
        }
    }
    [self validateSwitches];
}
-(void)validateSwitches
{
    // TouchID Requires ScreenSecurity to be enabled
    self.enableScreenSecuritySwitch.enabled = !Environment.preferences.touchIDSecurityIsEnabled;
    self.enableScreenSecuritySwitch.on = Environment.preferences.screenSecurityIsEnabled;
    self.enableTouchIDSecuritySwitch.on = Environment.preferences.touchIDSecurityIsEnabled;
}

#pragma mark - Timer

-(void)endTimer:(id)sender
{
    self.fingerprintCell.detailTextLabel.text =  NSLocalizedString(@"SETTINGS_FINGERPRINT_COPY",nil);
    [self.copiedTimer invalidate];
    self.copiedTimer = nil;
}

@end
