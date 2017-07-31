//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIPage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSTableSection;
@class TSThread;

@interface DebugUIPage : NSObject

- (NSString *)name;

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
