//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSData *_Nonnull (^DynamicOutgoingMessageBlock)(SignalServiceAddress *);

/// This class is only used in debug tools
@interface OWSDynamicOutgoingMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread plainTextDataBlock:(DynamicOutgoingMessageBlock)block;
- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
            plainTextDataBlock:(DynamicOutgoingMessageBlock)block;

@end

NS_ASSUME_NONNULL_END
