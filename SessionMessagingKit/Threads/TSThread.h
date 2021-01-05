//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SessionUtilitiesKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

BOOL IsNoteToSelfEnabled(void);

@class OWSDisappearingMessagesConfiguration;
@class TSInteraction;
@class TSInvalidIdentityKeyReceivingErrorMessage;

/**
 *  TSThread is the superclass of TSContactThread and TSGroupThread
 */
@interface TSThread : TSYapDatabaseObject

@property (nonatomic) BOOL shouldThreadBeVisible;
@property (nonatomic, readonly) NSDate *creationDate;
@property (nonatomic, readonly) BOOL isArchivedByLegacyTimestampForSorting;
@property (nonatomic, readonly) TSInteraction *lastInteraction;

/**
 *  Whether the object is a group thread or not.
 *
 *  @return YES if is a group thread, NO otherwise.
 */
- (BOOL)isGroupThread;

/**
 *  Returns the name of the thread.
 *
 *  @return The name of the thread.
 */
- (NSString *)name;

/**
 * @returns
 *   Signal Id (e164) of the contact if it's a contact thread.
 */
- (nullable NSString *)contactIdentifier;

/**
 * @returns recipientId for each recipient in the thread
 */
@property (nonatomic, readonly) NSArray<NSString *> *recipientIdentifiers;

- (BOOL)isNoteToSelf;

#pragma mark Interactions

- (void)enumerateInteractionsWithTransaction:(YapDatabaseReadTransaction *)transaction usingBlock:(void (^)(TSInteraction *interaction, YapDatabaseReadTransaction *transaction))block;

- (void)enumerateInteractionsUsingBlock:(void (^)(TSInteraction *interaction))block;

/**
 *  @return The number of interactions in this thread.
 */
- (NSUInteger)numberOfInteractions;

- (NSUInteger)unreadMessageCountWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(unreadMessageCount(transaction:));

- (void)markAllAsReadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Returns the string that will be displayed typically in a conversations view as a preview of the last message
 *received in this thread.
 *
 *  @return Thread preview string.
 */
- (NSString *)lastMessageTextWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(lastMessageText(transaction:));

- (nullable TSInteraction *)lastInteractionForInboxWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(lastInteractionForInbox(transaction:));

/**
 *  Updates the thread's caches of the latest interaction.
 *
 *  @param lastMessage Latest Interaction to take into consideration.
 *  @param transaction Database transaction.
 */
- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Archival

/**
 * @return YES if no new messages have been sent or received since the thread was last archived.
 */
- (BOOL)isArchivedWithTransaction:(YapDatabaseReadTransaction *)transaction;

/**
 *  Archives a thread
 *
 *  @param transaction Database transaction.
 */
- (void)archiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Unarchives a thread
 *
 *  @param transaction Database transaction.
 */
- (void)unarchiveThreadWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)removeAllThreadInteractionsWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

- (TSInteraction *)getLastInteractionWithTransaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark Disappearing Messages

- (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfigurationWithTransaction:
    (YapDatabaseReadTransaction *)transaction;
- (uint32_t)disappearingMessagesDurationWithTransaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark Drafts

/**
 *  Returns the last known draft for that thread. Always returns a string. Empty string if nil.
 *
 *  @param transaction Database transaction.
 *
 *  @return Last known draft for that thread.
 */
- (NSString *)currentDraftWithTransaction:(YapDatabaseReadTransaction *)transaction;

/**
 *  Sets the draft of a thread. Typically called when leaving a conversation view.
 *
 *  @param draftString Draft string to be saved.
 *  @param transaction Database transaction.
 */
- (void)setDraft:(NSString *)draftString transaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (atomic, readonly) BOOL isMuted;
@property (atomic, readonly, nullable) NSDate *mutedUntilDate;

#pragma mark - Update With... Methods

- (void)updateWithMutedUntilDate:(NSDate *)mutedUntilDate transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
