//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateChangeMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSVerificationStateChangeMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      recipientId:(NSString *)recipientId
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange
{
    OWSAssertDebug(recipientId.length > 0);

    self = [super initWithTimestamp:timestamp inThread:thread messageType:TSInfoMessageVerificationStateChange];
    if (!self) {
        return self;
    }

    _recipientId = recipientId;
    _verificationState = verificationState;
    _isLocalChange = isLocalChange;

    return self;
}

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
               verificationState:(enum OWSVerificationState)verificationState
{
    OWSAssertDebug(recipientId.length > 0);

    self = [super initWithUniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId
                     attachmentIds:attachmentIds
                              body:body
                      contactShare:contactShare
                   expireStartedAt:expireStartedAt
                         expiresAt:expiresAt
                  expiresInSeconds:expiresInSeconds
                       linkPreview:linkPreview
                     quotedMessage:quotedMessage
                     schemaVersion:schemaVersion
                     customMessage:customMessage
          infoMessageSchemaVersion:infoMessageSchemaVersion
                       messageType:messageType
                              read:read
           unregisteredRecipientId:unregisteredRecipientId];
    if (!self) {
        return self;
    }

    _recipientId = recipientId;
    _verificationState = verificationState;
    _isLocalChange = isLocalChange;

    return self;
}

@end

NS_ASSUME_NONNULL_END
