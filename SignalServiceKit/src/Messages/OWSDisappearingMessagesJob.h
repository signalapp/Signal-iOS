//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SignalServiceAddress;
@class TSMessage;
@class TSThread;

@protocol ContactsManagerProtocol;

@interface OWSDisappearingMessagesJob : NSObject

+ (instancetype)sharedJob;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)startAnyExpirationForMessage:(TSMessage *)message
                 expirationStartedAt:(uint64_t)expirationStartedAt
                         transaction:(SDSAnyWriteTransaction *_Nonnull)transaction;

/**
 * Synchronize our disappearing messages settings with that of the given message. Useful so we can
 * become eventually consistent with remote senders.
 *
 * @param duration
 *   Can be 0, indicating a non-expiring message, or greater, indicating an expiring message. We match the expiration
 *   timer of the message, including disabling expiring messages if the message is not an expiring message.
 *
 * @param remoteRecipient
 *    nil for outgoing messages, otherwise the address of the sender
 *
 * @param createdInExistingGroup
 *    YES when being added to a group which already has DM enabled, otherwise NO
 */
- (void)becomeConsistentWithDisappearingDuration:(uint32_t)duration
                                          thread:(TSThread *)thread
                        createdByRemoteRecipient:(nullable SignalServiceAddress *)remoteRecipient
                          createdInExistingGroup:(BOOL)createdInExistingGroup
                                     transaction:(SDSAnyWriteTransaction *)transaction;

// Clean up any messages that expired since last launch immediately
// and continue cleaning in the background.
- (void)startIfNecessary;

- (void)cleanupMessagesWhichFailedToStartExpiringWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)schedulePass;

@end

NS_ASSUME_NONNULL_END
