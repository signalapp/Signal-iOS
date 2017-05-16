//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSUnreadIndicatorInteraction : TSMessage

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
