//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSVerificationStateSyncMessage;
@class TSContactThread;

@interface OWSOutgoingNullMessage : TSOutgoingMessage

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

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage;

@end

NS_ASSUME_NONNULL_END
