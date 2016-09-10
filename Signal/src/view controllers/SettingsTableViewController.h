//
//  SettingsTableViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 03/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingsTableViewController : UITableViewController

@property (strong, nonatomic) IBOutlet UILabel *registeredName;
@property (strong, nonatomic) IBOutlet UILabel *registeredNumber;
@property (strong, nonatomic) IBOutlet UILabel *networkStatusLabel;
@property (strong, nonatomic) IBOutlet UILabel *networkStatusHeader;
@property (strong, nonatomic) IBOutlet UILabel *privacyLabel;
@property (strong, nonatomic) IBOutlet UILabel *notificationsLabel;
@property (strong, nonatomic) IBOutlet UILabel *linkedDevicesLabel;
@property (strong, nonatomic) IBOutlet UILabel *advancedLabel;
@property (strong, nonatomic) IBOutlet UILabel *aboutLabel;
@property (strong, nonatomic) IBOutlet UIButton *destroyAccountButton;

- (IBAction)unregisterUser:(id)sender;

@end
