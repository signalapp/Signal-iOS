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
    if (self.toggle) {
        [self.toggle setOn:[Environment.preferences screenSecurityIsEnabled]];
        [self.toggle addTarget:self action:@selector(toggleSetting:) forControlEvents:UIControlEventValueChanged];
    }

    if ([self.reuseIdentifier isEqualToString:@"imageUploadQuality"]) {
        [self updateImageQualityLabel];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}

#pragma mark - UISwitch

- (void)toggleSetting:(id)sender {
    if ([self.reuseIdentifier isEqualToString:@"enableScreenSecurity"]) {
        [Environment.preferences setScreenSecurity:self.toggle.isOn];
    }
}

#pragma mark - Detail Label

- (void)updateImageQualityLabel {
    /* this is currently unused, thus unlocalized. code should probably be excised as this will never be part of design
     */
    switch ([Environment.preferences imageUploadQuality]) {
        case TSImageQualityUncropped:
            self.detailLabel.text = @"Full";
            break;
        case TSImageQualityHigh:
            self.detailLabel.text = @"High";
            break;
        case TSImageQualityMedium:
            self.detailLabel.text = @"Medium";
            break;
        case TSImageQualityLow:
            self.detailLabel.text = @"Low";
            break;
        default:
            DDLogWarn(@"Unknown Image Quality setting : %lu <%s>",
                      [Environment.preferences imageUploadQuality],
                      __PRETTY_FUNCTION__);
            break;
    }
}

@end
