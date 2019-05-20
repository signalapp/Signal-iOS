//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDeliveryReceipt;

@interface OWSReceiptsForSenderMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(nullable TSThread *)thread
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                 expireStartedAt:(uint64_t)expireStartedAt
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                                  messageSticker:(nullable MessageSticker *)messageSticker
                                ephemeralMessage:(nullable EphemeralMessage *)ephemeralMessage NS_UNAVAILABLE;

+ (OWSReceiptsForSenderMessage *)deliveryReceiptsForSenderMessageWithThread:(nullable TSThread *)thread
                                                          messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps;

+ (OWSReceiptsForSenderMessage *)readReceiptsForSenderMessageWithThread:(nullable TSThread *)thread
                                                      messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps;

@end

NS_ASSUME_NONNULL_END
