//
//  SettingsTableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewCell.h"

#import "Environment.h"
#import "PreferencesUtil.h"

@implementation SettingsTableViewCell

- (void)awakeFromNib {
    // Initialization code
    [self.toggle setOn:[Environment.preferences screenSecurityIsEnabled]];
    [self.toggle addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];

}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

#pragma mark - UISwitch

-(void)toggleSetting:(id)sender
{
    if ([self.reuseIdentifier isEqualToString:@"enableScreenSecurity"]) {
        [Environment.preferences setScreenSecurity:self.toggle.isOn];
    }
}


@end
