//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSThreadAvatarChangedNotification;
extern NSString *const TSThread_NotificationKey_UniqueId;

@class OWSDisappearingMessagesConfiguration;
@class TSInteraction;
@class TSInvalidIdentityKeyReceivingErrorMessage;

/**
 *  TSThread is the superclass of TSContactThread and TSGroupThread
 */

@interface TSThread : TSYapDatabaseObject

// YES IFF this thread has ever had a message.
@property (nonatomic) BOOL hasEverHadMessage;

/**
 *  Returns the title of the thread.
 *
 *  @return The title of the thread.
 */
//- (NSString *)name;
@property (nullable) NSString *title;

/**
 * Type of thread/conversation
 * "conversation" or "announcement"
 */
@property (nonnull) NSString *type;

/**
 *  Returns the image representing the thread. Nil if not available.
 *
 *  @return UIImage of the thread, or nil.
 */
@property (nullable) UIImage *image;

@property (readonly, nullable) NSString *conversationColorName;
- (void)updateConversationColorName:(NSString *)colorName transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;
+ (NSString *)stableConversationColorNameForString:(NSString *)colorSeed;

/**
 * @returns recipientId for each recipient in the thread
 */
@property (nonatomic, readonly) NSArray<NSString *> *recipientIdentifiers;

#pragma mark Interactions

/**
 *  @return The number of interactions in this thread.
 */
- (NSUInteger)numberOfInteractions;

/**
 * Get all messages in the thread we weren't able to decrypt
 */
- (nonnull NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *)receivedMessagesForInvalidKey:(NSData *)key;

- (NSUInteger)unreadMessageCountWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(unreadMessageCount(transaction:));

- (BOOL)hasSafetyNumbers;

- (void)markAllAsReadWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Returns the latest date of a message in the thread or the thread creation date if there are no messages in that
 *thread.
 *
 *  @return The date of the last message or thread creation date.
 */
- (nonnull NSDate *)lastMessageDate;

/**
 *  Returns the string that will be displayed typically in a conversations view as a preview of the last message
 *received in this thread.
 *
 *  @return Thread preview string.
 */
- (nonnull NSString *)lastMessageTextWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(lastMessageText(transaction:));

- (nullable TSInteraction *)lastInteractionForInboxWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(lastInteractionForInbox(transaction:));

/**
 *  Updates the thread's caches of the latest interaction.
 *
 *  @param lastMessage Latest Interaction to take into consideration.
 *  @param transaction Database transaction.
 */
- (void)updateWithLastMessage:(TSInteraction *)lastMessage transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

#pragma mark Archival

/**
 *  Returns the last date at which a string was archived or nil if the thread was never archived or brought back to the
 *inbox.
 *
 *  @return Last archival date.
 */
- (nullable NSDate *)archivalDate;

/**
 *  Archives a thread with the current date.
 *
 *  @param transaction Database transaction.
 */
- (void)archiveThreadWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Archives a thread with the reference date. This is currently only used for migrating older data that has already
 * been archived.
 *
 *  @param transaction Database transaction.
 *  @param date        Date at which the thread was archived.
 */
- (void)archiveThreadWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction referenceDate:(nonnull NSDate *)date;

/**
 *  Unarchives a thread that was archived previously.
 *
 *  @param transaction Database transaction.
 */
- (void)unarchiveThreadWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

- (void)removeAllThreadInteractionsWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;


#pragma mark Disappearing Messages

- (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfigurationWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction;
- (uint32_t)disappearingMessagesDurationWithTransaction:(nonnull YapDatabaseReadTransaction *)transaction;

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
- (void)setDraft:(NSString *)draftString transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

@property (atomic, readonly) BOOL isMuted;
@property (atomic, readonly, nullable) NSDate *mutedUntilDate;

#pragma mark - Update With... Methods

- (void)updateWithMutedUntilDate:(NSDate *)mutedUntilDate transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

// MARK: Forsta additions
@property (nonnull) NSArray<NSString *> *participantIds;
@property (nullable) NSString *universalExpression;
@property (nullable) NSString *prettyExpression;
@property (readonly, nonnull) NSString *displayName;
@property (nonnull) NSCountedSet *monitorIds;
@property (nullable) NSNumber *pinPosition;

/**
 *  Get or create thread with array of participant UUIDs
 */
+(instancetype)getOrCreateThreadWithParticipants:(nonnull NSArray <NSString *> *)participantIDs
                                     transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;
/**
 *  Get or create thread with thread UUID
 */
+(instancetype)getOrCreateThreadWithId:(nonnull NSString *)threadId;
+(instancetype)getOrCreateThreadWithId:(nonnull NSString *)threadId
                           transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Remove participant from thread
 */
-(void)removeMembers:(nonnull NSSet *)leavingMemberIds
         transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

/**
 *  Update avatar/image wiht attachment stream
 */
-(void)updateImageWithAttachmentStream:(NSString *)attachmentStream;

/**
 *  Validate and update a thread
 */
-(void)validateWithTransaction:(nonnull YapDatabaseReadWriteTransaction *)transaction;

-(void)updateWithPayload:(nonnull NSDictionary *)payload;

/**
 * thread containing participant id
 */
+(NSArray *)threadsContainingParticipant:(NSString *)participantId transaction:transaction;

@end

NS_ASSUME_NONNULL_END
