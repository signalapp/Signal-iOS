//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

@class TSGroupThread;

@interface ShowGroupMembersViewController : OWSTableViewController

- (void)configWithThread:(TSGroupThread *)thread;

@end
