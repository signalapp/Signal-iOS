//
//  SettingsTableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewCell.h"

@implementation SettingsTableViewCell

- (void)awakeFromNib {
    // Initialization code
    
    [self.toggle addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
    
    [self.profileImageView.layer setCornerRadius:50.0f];
    [self.profileImageView.layer setMasksToBounds:YES];
    
    [self.changeProfileImageViewButton addTarget:self action:@selector(changeImageView:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

#pragma mark - UISwitch

-(void)toggleSetting:(id)sender
{
    if ([self.reuseIdentifier isEqualToString:@"hideContactImages"])
    {
        self.state.text = self.toggle.isOn ? @"Yes" : @"No";
    }
}

#pragma mark - Editing Profile 
-(void)changeImageView:(id)sender
{
    NSLog(@"hi");

}

@end
