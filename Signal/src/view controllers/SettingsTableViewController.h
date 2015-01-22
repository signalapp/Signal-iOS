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

-(IBAction)unregisterUser:(id)sender;
@end
