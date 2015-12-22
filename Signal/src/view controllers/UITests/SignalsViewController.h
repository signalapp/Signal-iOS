//
//  SignalsViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#include "InboxTableViewCell.h"

#import "CallState.h"
#import "Contact.h"
#import "TSGroupModel.h"

@interface SignalsViewController : UIViewController <UITableViewDelegate,
                                                     UITableViewDataSource,
                                                     TableViewCellDelegate,
                                                     UIViewControllerPreviewingDelegate>

@property (nonatomic) NSString *contactIdentifierFromCompose;
@property (nonatomic) TSGroupModel *groupFromCompose;
@property (nonatomic) BOOL composeMessage;

@property (nonatomic, retain) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UILabel *emptyBoxLabel;

@property (nonatomic, retain) CallState *latestCall;

- (NSNumber *)updateInboxCountLabel;
- (void)composeNew;

@end
