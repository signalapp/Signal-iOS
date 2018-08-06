//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

@interface TSErrorMessage ()

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType NS_DESIGNATED_INITIALIZER;

@property (atomic, nullable) NSData *envelopeData;

@property NSDictionary *pendingOutgoingMessage;

#define TSPendingOutgoingMessageKey @"TSPendingOutgoingMessageKey"
#define TSPendingOutgoingMessageRecipientKey @"TSPendingOutgoingMessageRecipientKey"

@end
