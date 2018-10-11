//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@protocol ContactsManagerProtocol;

@interface OWSDisappearingMessagesJob : NSObject

+ (instancetype)sharedJob;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

- (void)startAnyExpirationForMessage:(TSMessage *)message
                 expirationStartedAt:(uint64_t)expirationStartedAt
                         transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction;

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
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
                                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Synchronize our disappearing messages settings with that of the given message. Useful so we can
 * become eventually consistent with remote senders.
 *
 * @param duration
 *   Can be 0, indicating a non-expiring message, or greater, indicating an expiring message. We match the expiration
 * timer of the message, including disabling expiring messages if the message is not an expiring message.
 *
 * @param timestampForSorting
 *   timestampForSorting of the message before which we want to appear.
 *
 * @param remoteContactName
 *    nil for outgoing messages, otherwise the name of the sender
 * @param createdInExistingGroup
 *    YES when being added to a group which already has DM enabled, otherwise NO
 */
- (void)becomeConsistentWithDisappearingDuration:(uint32_t)duration
                                          thread:(TSThread *)thread
                           appearBeforeTimestamp:(uint64_t)timestampForSorting
                      createdByRemoteContactName:(nullable NSString *)remoteContactName
                          createdInExistingGroup:(BOOL)createdInExistingGroup
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction;

// Clean up any messages that expired since last launch immediately
// and continue cleaning in the background.
- (void)startIfNecessary;

- (void)cleanupMessagesWhichFailedToStartExpiringWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
