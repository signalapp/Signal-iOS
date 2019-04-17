//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;
@class TSThread;

@interface OWSDisappearingConfigurationUpdateInfoMessage : TSInfoMessage

@property (nonatomic, readonly) BOOL configurationIsEnabled;

/**
 * @param remoteName is nil when created by the local user
 */
// MJK TODO - can we remove sendertimestamp here
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    configuration:(OWSDisappearingMessagesConfiguration *)configuration
              createdByRemoteName:(nullable NSString *)remoteName
           createdInExistingGroup:(BOOL)createdInExistingGroup;

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
                   customMessage:(nullable NSString *)customMessage
        infoMessageSchemaVersion:(NSUInteger)infoMessageSchemaVersion
                     messageType:(TSInfoMessageType)messageType
                            read:(BOOL)read
         unregisteredRecipientId:(nullable NSString *)unregisteredRecipientId
    configurationDurationSeconds:(unsigned int)configurationDurationSeconds
          configurationIsEnabled:(BOOL)configurationIsEnabled
             createdByRemoteName:(nullable NSString *)createdByRemoteName
          createdInExistingGroup:(BOOL)createdInExistingGroup
NS_SWIFT_NAME(init(uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:contactShare:expireStartedAt:expiresAt:expiresInSeconds:linkPreview:quotedMessage:schemaVersion:customMessage:infoMessageSchemaVersion:messageType:read:unregisteredRecipientId:configurationDurationSeconds:configurationIsEnabled:createdByRemoteName:createdInExistingGroup:));

// clang-format on

// --- CODE GENERATION MARKER

@end

NS_ASSUME_NONNULL_END
