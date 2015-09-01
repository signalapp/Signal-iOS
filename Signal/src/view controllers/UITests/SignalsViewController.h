//
//  SignalsViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#include "InboxTableViewCell.h"
#import <UIKit/UIKit.h>

#import "Contact.h"
#import "TSGroupModel.h"
#import "CallState.h"

@interface SignalsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, TableViewCellDelegate>

@property (nonatomic) NSString        *contactIdentifierFromCompose;
@property (nonatomic) TSGroupModel    *groupFromCompose;
@property (nonatomic) BOOL            composeMessage;

@property (nonatomic, retain) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UILabel *emptyBoxLabel;

@property (nonatomic, retain) CallState* latestCall;

- (NSNumber*)updateInboxCountLabel;

@end
