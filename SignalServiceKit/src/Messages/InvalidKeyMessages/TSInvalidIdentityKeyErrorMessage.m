//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

// --- CODE GENERATION MARKER

// clang-format off

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
       errorMessageSchemaVersion:(NSUInteger)errorMessageSchemaVersion
                       errorType:(TSErrorMessageType)errorType
                            read:(BOOL)read
                     recipientId:(nullable NSString *)recipientId
{
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
         errorMessageSchemaVersion:errorMessageSchemaVersion
                         errorType:errorType
                              read:read
                       recipientId:recipientId];

    if (!self) {
        return self;
    }

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (void)throws_acceptNewIdentityKey
{
    OWSAbstractMethod();
}

- (nullable NSData *)throws_newIdentityKey
{
    OWSAbstractMethod();
    return nil;
}

- (NSString *)theirSignalId
{
    OWSAbstractMethod();
    return nil;
}

@end

NS_ASSUME_NONNULL_END
