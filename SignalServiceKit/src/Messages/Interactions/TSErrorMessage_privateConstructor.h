//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSErrorMessage ()

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
