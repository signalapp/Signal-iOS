//
//  TSErrorMessage_privateConstructor.h
//  Signal
//
//  Created by Frederic Jacobs on 31/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

@interface TSErrorMessage ()

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType NS_DESIGNATED_INITIALIZER;

@property NSData *pushSignal;

@property NSDictionary *pendingOutgoingMessage;

#define TSPendingOutgoingMessageKey @"TSPendingOutgoingMessageKey"
#define TSPendingOutgoingMessageRecipientKey @"TSPendingOutgoingMessageRecipientKey"

@end
