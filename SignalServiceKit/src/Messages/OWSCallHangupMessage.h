//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageHangup;

/**
 * Sent by either party in a call to indicate the user intentionally ended the call.
 */
@interface OWSCallHangupMessage : OWSOutgoingCallMessage

- (instancetype)initWithCallId:(UInt64)callId;

@property (nonatomic, readonly) UInt64 callId;

- (nullable SSKProtoCallMessageHangup *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
