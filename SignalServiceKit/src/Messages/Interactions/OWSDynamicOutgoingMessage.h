//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosDataMessageBuilder;
@class SignalRecipient;

typedef NSData *_Nonnull (^DynamicOutgoingMessageBlock)(SignalRecipient *);

@interface OWSDynamicOutgoingMessage : TSOutgoingMessage

- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block inThread:(nullable TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
