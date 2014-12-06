//
//  SettingsTableViewCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingsTableViewCell : UITableViewCell

//Regular cell
@property(nonatomic, strong) IBOutlet UISwitch* toggle;

@end
