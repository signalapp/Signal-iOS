//
//  ContactDetailCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 30/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "Contact.h"
#import "UIUtil.h"

@interface ContactDetailCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel *contactName;
@property (strong, nonatomic) IBOutlet UIImageView *contactImageView;
@property (strong, nonatomic) IBOutlet UIImageView *contactFavoriteImageView;
@property (strong, nonatomic) IBOutlet UILabel *contactPhoneNumber;
@property (strong, nonatomic) IBOutlet UIButton *contactTextButton;
@property (strong, nonatomic) IBOutlet UIButton *contactCallButton;
@property (strong, nonatomic) IBOutlet UITextView *contactNotesTextView;


@end
