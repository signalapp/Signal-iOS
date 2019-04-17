//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoEnvelope;

// DEPRECATED - we no longer create new instances of this class (as of  mid-2017); However, existing instances may
// exist, so we should keep this class around to honor their old behavior.
__attribute__((deprecated)) @interface TSInvalidIdentityKeyReceivingErrorMessage : TSInvalidIdentityKeyErrorMessage

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
                        authorId:(NSString *)authorId
                    envelopeData:(nullable NSData *)envelopeData
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:errorMessageSchemaVersion:errorType:read:recipientId:authorId:envelopeData:));

// clang-format on

// --- CODE GENERATION MARKER

#ifdef DEBUG
+ (nullable instancetype)untrustedKeyWithEnvelope:(SSKProtoEnvelope *)envelope
                                  withTransaction:(YapDatabaseReadWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
