//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSProfileKeyMessage : TSOutgoingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
