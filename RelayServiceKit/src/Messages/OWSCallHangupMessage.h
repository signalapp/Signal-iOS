//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingCallMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageHangup;

/**
 * Sent by either party in a call to indicate the user intentionally ended the call.
 */
@interface OWSCallHangupMessage : OWSOutgoingCallMessage

- (instancetype)initWithPeerId:(NSString *)peerId;

@property (nonatomic, readonly, copy) NSString *peerId;

- (OWSSignalServiceProtosCallMessageHangup *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
