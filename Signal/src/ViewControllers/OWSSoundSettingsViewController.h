//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSSoundType) { OWSSoundType_Notification = 0 };

@class TSThread;

@interface OWSSoundSettingsViewController : OWSTableViewController

@property (nonatomic) OWSSoundType soundType;

// This property is optional.  If it is not set, we are
// editing the global notification sound.
@property (nonatomic, nullable) TSThread *thread;

@end

NS_ASSUME_NONNULL_END
