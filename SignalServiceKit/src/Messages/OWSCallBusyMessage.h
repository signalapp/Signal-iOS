//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageBusy;

/**
 * Sent by the call recipient after receiving a call offer when they are already in a call.
 */
@interface OWSCallBusyMessage : OWSOutgoingCallMessage

- (instancetype)initWithCallId:(UInt64)callId;

@property (nonatomic, readonly) UInt64 callId;

- (nullable SSKProtoCallMessageBusy *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
