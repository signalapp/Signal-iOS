//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSVerificationStateChangeMessage : TSInfoMessage

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) BOOL isLocalChange;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      recipientId:(NSString *)recipientId
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(unsigned long long)receivedAtTimestamp
                          sortId:(unsigned long long)sortId
                       timestamp:(unsigned long long)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                    contactShare:(nullable OWSContact *)contactShare
                 expireStartedAt:(unsigned long long)expireStartedAt
                       expiresAt:(unsigned long long)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                   schemaVersion:(NSUInteger)schemaVersion
                   customMessage:(nullable NSString *)customMessage
        infoMessageSchemaVersion:(NSUInteger)infoMessageSchemaVersion
                     messageType:(enum TSInfoMessageType)messageType
                            read:(BOOL)read
         unregisteredRecipientId:(nullable NSString *)unregisteredRecipientId
                   isLocalChange:(BOOL)isLocalChange
                     recipientId:(NSString *)recipientId
               verificationState:(enum OWSVerificationState)verificationState NS_DESIGNATED_INITIALIZER
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:customMessage:infoMessageSchemaVersion:messageType:read:unregisteredRecipientId:isLocalChange:recipientId:verificationState:));

@end

NS_ASSUME_NONNULL_END
