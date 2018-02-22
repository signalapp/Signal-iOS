//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

@class TSThread;

@interface NotificationSoundsViewController : OWSTableViewController

// This property is optional.  If it is not set, we are
// editing the global notification sound.
@property (nonatomic, nullable) TSThread *thread;

@end
