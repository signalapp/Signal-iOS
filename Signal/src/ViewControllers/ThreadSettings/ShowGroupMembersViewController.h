//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

@class TSGroupThread;

// GroupsV2 TODO: Remove this VC.
@interface ShowGroupMembersViewController : OWSTableViewController

- (void)configWithThread:(TSGroupThread *)thread;

@end
