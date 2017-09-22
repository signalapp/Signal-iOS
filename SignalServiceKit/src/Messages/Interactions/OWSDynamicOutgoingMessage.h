//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosDataMessageBuilder;
@class SignalRecipient;

typedef NSData *_Nonnull (^DynamicOutgoingMessageBlock)(SignalRecipient *);

@interface OWSDynamicOutgoingMessage : TSOutgoingMessage

- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block thread:(nullable TSThread *)thread;
- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block
                    timestamp:(uint64_t)timestamp
                       thread:(nullable TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
