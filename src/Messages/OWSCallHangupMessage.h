//  Created by Michael Kirk on 12/8/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageHangup;

@interface OWSCallHangupMessage : OWSOutgoingCallMessage

- (instancetype)initWithCallId:(UInt64)callId;

@property (nonatomic, readonly) UInt64 callId;

- (OWSSignalServiceProtosCallMessageHangup *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
