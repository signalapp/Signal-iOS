//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

// A generic, serializable message that can be used to
// send fixed plaintextData payloads.
@interface OWSStaticOutgoingMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread plaintextData:(NSData *)plaintextData;
- (instancetype)initWithThread:(TSThread *)thread timestamp:(uint64_t)timestamp plaintextData:(NSData *)plaintextData;

@end

NS_ASSUME_NONNULL_END
