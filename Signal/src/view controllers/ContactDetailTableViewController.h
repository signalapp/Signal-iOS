//
//  ContactDetailTableViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 30/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "Contact.h"

@interface ContactDetailTableViewController : UITableViewController

@property (nonatomic, strong) Contact *contact;

@end
