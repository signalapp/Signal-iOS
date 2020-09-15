//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSSoundSettingsViewController : OWSTableViewController

// This property is optional.  If it is not set, we are
// editing the global notification sound.
@property (nonatomic, nullable) TSThread *thread;

@end

NS_ASSUME_NONNULL_END
