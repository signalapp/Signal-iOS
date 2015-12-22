//
//  SettingsTableViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 03/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingsTableViewController : UITableViewController

@property IBOutlet UILabel *registeredName;
@property IBOutlet UILabel *registeredNumber;
@property IBOutlet UILabel *networkStatusLabel;

@property IBOutlet UILabel *networkStatusHeader;
@property IBOutlet UILabel *settingsPrivacyTitle;
@property IBOutlet UILabel *settingsNotifications;
@property IBOutlet UILabel *settingsAdvancedTitle;
@property IBOutlet UILabel *settingsAboutTitle;
@property IBOutlet UIButton *destroyAccountButton;

- (IBAction)unregisterUser:(id)sender;
- (IBAction)unwindToUserCancelledChangeNumber:(UIStoryboardSegue *)segue;
@end
