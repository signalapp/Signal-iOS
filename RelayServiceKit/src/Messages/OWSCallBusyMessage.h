//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageBusy;

/**
 * Sent by the call recipient after receiving a call offer when they are already in a call.
 */
@interface OWSCallBusyMessage : OWSOutgoingCallMessage

- (instancetype)initWithPeerId:(NSString *)peerId;

@property (nonatomic, readonly, copy) NSString *peerId;

- (OWSSignalServiceProtosCallMessageBusy *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
