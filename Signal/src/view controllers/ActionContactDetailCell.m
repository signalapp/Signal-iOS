//
//  ActionContactDetailCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 09/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "DJWActionSheet.h"
#import "ActionContactDetailCell.h"


@implementation ActionContactDetailCell

- (void)awakeFromNib {
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


-(IBAction)messageButtonTapped:(id)sender
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

-(IBAction)callButtonTapped:(id)sender
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}


@end
