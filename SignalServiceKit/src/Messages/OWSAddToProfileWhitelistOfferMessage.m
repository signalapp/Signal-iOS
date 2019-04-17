//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAddToProfileWhitelistOfferMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation OWSAddToProfileWhitelistOfferMessage
#pragma clang diagnostic pop

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
                       contactId:(NSString *)contactId
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
                     customMessage:customMessage
          infoMessageSchemaVersion:infoMessageSchemaVersion
                       messageType:messageType
                              read:read
           unregisteredRecipientId:unregisteredRecipientId];

    if (!self) {
        return self;
    }

    _contactId = contactId;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (instancetype)addToProfileWhitelistOfferMessageWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread
{
    return [[OWSAddToProfileWhitelistOfferMessage alloc]
        initWithTimestamp:timestamp
                 inThread:thread
              messageType:(thread.isGroupThread ? TSInfoMessageAddGroupToProfileWhitelistOffer
                                                : TSInfoMessageAddUserToProfileWhitelistOffer)];
}

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
