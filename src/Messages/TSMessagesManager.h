//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSOutgoingMessage.h"

@class TSCall;
@class YapDatabaseConnection;
@class OWSSignalServiceProtosEnvelope;
@class OWSSignalServiceProtosDataMessage;

@interface TSMessagesManager : NSObject

+ (instancetype)sharedManager;

@property (readonly) YapDatabaseConnection *dbConnection;

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;

- (void)processException:(NSException *)exception
         outgoingMessage:(TSOutgoingMessage *)message
                inThread:(TSThread *)thread;

/**
 * Processes all kinds of incoming envelopes with a data message, along with any attachments.
 *
 * @returns
 *   If an incoming message is created, it will be returned. If it is, for example, a group update,
 *   no incoming message is created, so nil will be returned.
 */
- (TSIncomingMessage *)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                              withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                attachmentIds:(NSArray<NSString *> *)attachmentIds;

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

@end
