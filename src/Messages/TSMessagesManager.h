//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSNetworkManager;
@class TSStorageManager;
@class OWSSignalServiceProtosEnvelope;
@class OWSSignalServiceProtosDataMessage;
@class ContactsUpdater;
@class OWSDisappearingMessagesJob;
@protocol ContactsManagerProtocol;

@interface TSMessagesManager : NSObject

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;

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

/**
 * @returns
 *   Group or Contact thread for message, creating a new one if necessary.
 */
- (TSThread *)threadForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                    dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage;

/**
 * Synchronize our disappearing messages settings with that of the given message. Useful so we can
 * become eventually consistent with remote senders.
 *
 * @param message
 *   Can be an expiring or non expiring message. We match the expiration timer of the message, including disabling
 *   expiring messages if the message is not an expiring message.
 */
- (void)becomeConsistentWithDisappearingConfigurationForMessage:(TSMessage *)message;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
