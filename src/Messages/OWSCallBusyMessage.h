//  Created by Michael Kirk on 12/1/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageBusy;

@interface OWSCallBusyMessage : OWSOutgoingCallMessage

- (instancetype)initWithCallId:(UInt64)callId;

@property (nonatomic, readonly) UInt64 callId;

- (OWSSignalServiceProtosCallMessageBusy *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
