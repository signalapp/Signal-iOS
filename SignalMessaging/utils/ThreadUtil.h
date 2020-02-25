//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSContact;
@class OWSLinkPreviewDraft;
@class OWSMessageSender;
@class OWSQuotedReplyModel;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignalAttachment;
@class SignalServiceAddress;
@class StickerInfo;
@class TSContactThread;
@class TSGroupThread;
@class TSInteraction;
@class TSOutgoingMessage;
@class TSThread;
@class YapDatabaseReadTransaction;

#pragma mark -

@interface ThreadUtil : NSObject

#pragma mark - Durable Message Enqueue

+ (TSOutgoingMessage *)enqueueMessageWithText:(NSString *)fullMessageText
                                     inThread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction;

+ (TSOutgoingMessage *)enqueueMessageWithText:(nullable NSString *)fullMessageText
                             mediaAttachments:(NSArray<SignalAttachment *> *)attachments
                                     inThread:(TSThread *)thread
                             quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                             linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                  transaction:(SDSAnyReadTransaction *)transaction;

+ (nullable TSOutgoingMessage *)createUnsentMessageWithText:(nullable NSString *)fullMessageText
                                           mediaAttachments:(NSArray<SignalAttachment *> *)mediaAttachments
                                                   inThread:(TSThread *)thread
                                           quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                           linkPreviewDraft:(nullable nullable OWSLinkPreviewDraft *)linkPreviewDraft
                                                transaction:(SDSAnyWriteTransaction *)transaction
                                                      error:(NSError **)error;

+ (TSOutgoingMessage *)enqueueMessageWithContactShare:(OWSContact *)contactShare inThread:(TSThread *)thread;

+ (TSOutgoingMessage *)enqueueMessageWithInstalledSticker:(StickerInfo *)stickerInfo inThread:(TSThread *)thread;
+ (TSOutgoingMessage *)enqueueMessageWithUninstalledSticker:(StickerInfo *)stickerInfo
                                                stickerData:(NSData *)stickerData
                                                   inThread:(TSThread *)thread;

#pragma mark - Non-Durable Sending

// Used by SAE and "reply from lockscreen", otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithText:(NSString *)fullMessageText
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                         transaction:(SDSAnyReadTransaction *)transaction
                                       messageSender:(OWSMessageSender *)messageSender
                                          completion:(void (^)(NSError *_Nullable error))completion;

// Used by SAE, otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithText:(NSString *)fullMessageText
                                    mediaAttachments:(NSArray<SignalAttachment *> *)attachments
                                            inThread:(TSThread *)thread
                                    quotedReplyModel:(nullable OWSQuotedReplyModel *)quotedReplyModel
                                         transaction:(SDSAnyReadTransaction *)transaction
                                       messageSender:(OWSMessageSender *)messageSender
                                          completion:(void (^)(NSError *_Nullable error))completion;

// Used by SAE, otherwise we should use the durable `enqueue` counterpart
+ (TSOutgoingMessage *)sendMessageNonDurablyWithContactShare:(OWSContact *)contactShare
                                                    inThread:(TSThread *)thread
                                               messageSender:(OWSMessageSender *)messageSender
                                                  completion:(void (^)(NSError *_Nullable error))completion;

#pragma mark - Profile Whitelist

// This method should be called right _before_ we send a message to a thread,
// since we want to auto-add any thread to the profile whitelist that was
// initiated by the local user OR if there was a pending message request and
// the local user took an action like initiating a call or updating the DM timer.
//
// Returns YES IFF the thread was just added to the profile whitelist.
+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:(TSThread *)thread;
+ (BOOL)addThreadToProfileWhitelistIfEmptyOrPendingRequest:(TSThread *)thread
                                               transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Delete Content

+ (void)deleteAllContent;

#pragma mark - Find Content

+ (nullable TSInteraction *)findInteractionInThreadByTimestamp:(uint64_t)timestamp
                                                 authorAddress:(SignalServiceAddress *)authorAddress
                                                threadUniqueId:(NSString *)threadUniqueId
                                                   transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
