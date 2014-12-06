//
//  ActionContactDetailCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 09/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ActionContactDetailCell : UITableViewCell
@property (strong, nonatomic) IBOutlet UIButton *contactTextButton;
@property (strong, nonatomic) IBOutlet UIButton *contactCallButton;
@property (strong, nonatomic) IBOutlet UIButton *contactShredButton;
@end
