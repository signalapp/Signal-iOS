//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSErrorMessage ()

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType NS_DESIGNATED_INITIALIZER;

@property (atomic, nullable) NSData *envelopeData;

@end

NS_ASSUME_NONNULL_END
