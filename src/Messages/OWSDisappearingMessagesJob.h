//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSMessage;
@class TSThread;
@protocol ContactsManagerProtocol;

@interface OWSDisappearingMessagesJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager NS_DESIGNATED_INITIALIZER;

- (void)run;
- (void)setExpirationsForThread:(TSThread *)thread;
- (void)setExpirationForMessage:(TSMessage *)message;
- (void)setExpirationForMessage:(TSMessage *)message expirationStartedAt:(uint64_t)expirationStartedAt;
- (void)runBy:(uint64_t)millisecondTimestamp;


/**
 * Synchronize our disappearing messages settings with that of the given message. Useful so we can
 * become eventually consistent with remote senders.
 *
 * @param message
 *   Can be an expiring or non expiring message. We match the expiration timer of the message, including disabling
 *   expiring messages if the message is not an expiring message.
 *
 * @param contactsManager
 *   Provides the contact name responsible for any configuration changes in an info message.
 */
- (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager;

@end

NS_ASSUME_NONNULL_END
