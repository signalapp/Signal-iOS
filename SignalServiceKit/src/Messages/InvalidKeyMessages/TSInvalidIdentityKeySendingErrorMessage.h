//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class PreKeyBundle;
@class TSOutgoingMessage;
@class TSThread;

extern NSString *TSInvalidPreKeyBundleKey;
extern NSString *TSInvalidRecipientKey;

// DEPRECATED - we no longer create new instances of this class (as of  mid-2017); However, existing instances may
// exist, so we should keep this class around to honor their old behavior.
__attribute__((deprecated)) @interface TSInvalidIdentityKeySendingErrorMessage : TSInvalidIdentityKeyErrorMessage

@property (nonatomic, readonly) NSString *messageId;

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
                       errorType:(enum TSErrorMessageType)errorType
                            read:(BOOL)read
                     recipientId:(nullable NSString *)recipientId
                       messageId:(NSString *)messageId
                    preKeyBundle:(PreKeyBundle *)preKeyBundle
NS_DESIGNATED_INITIALIZER 
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:errorMessageSchemaVersion:errorType:read:recipientId:messageId:preKeyBundle:));

// clang-format on

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
