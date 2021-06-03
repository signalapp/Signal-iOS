//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

@class TSContactThread;

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingSenderKeyDistributionMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSContactThread *)destinationThread
    senderKeyDistributionMessageBytes:(NSData *)skdmBytes;

@end

NS_ASSUME_NONNULL_END
