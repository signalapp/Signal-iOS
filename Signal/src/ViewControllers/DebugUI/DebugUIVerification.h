//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;

@interface DebugUIVerification : NSObject

+ (OWSTableSection *)sectionForThread:(TSContactThread *)thread;

@end

NS_ASSUME_NONNULL_END
