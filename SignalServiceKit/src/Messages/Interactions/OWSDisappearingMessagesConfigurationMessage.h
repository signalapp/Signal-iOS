//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;

@interface OWSDisappearingMessagesConfigurationMessage : TSOutgoingMessage

// MJK TODO - remove senderTimestamp
- (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(TSThread *)thread
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                 expireStartedAt:(uint64_t)expireStartedAt
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                    contactShare:(nullable OWSContact *)contactShare
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                                  messageSticker:(nullable MessageSticker *)messageSticker NS_UNAVAILABLE;

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration thread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
