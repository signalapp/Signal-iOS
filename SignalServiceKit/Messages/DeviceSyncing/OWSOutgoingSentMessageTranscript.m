//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingSentMessageTranscript.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 *
 * recipientId is nil when building "sent" sync messages for messages
 * sent to groups.
 */
- (nullable SSKProtoDataMessage *)buildDataMessage:(TSThread *)thread transaction:(DBReadTransaction *)transaction;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript ()

// sentRecipientAddress is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) SignalServiceAddress *sentRecipientAddress;

@end

#pragma mark -

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                      messageThread:(TSThread *)messageThread
                    outgoingMessage:(TSOutgoingMessage *)message
                  isRecipientUpdate:(BOOL)isRecipientUpdate
                        transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(localThread != nil);
    OWSAssertDebug(messageThread != nil);

    // The sync message's timestamp must match the original outgoing message's timestamp.
    self = [super initWithTimestamp:message.timestamp localThread:localThread transaction:transaction];

    if (!self) {
        return self;
    }

    _message = message;
    _messageThread = messageThread;
    _isRecipientUpdate = isRecipientUpdate;

    if ([messageThread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)messageThread;
        _sentRecipientAddress = contactThread.contactAddress;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    return nil;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.isRecipientUpdate;
    result ^= self.message.hash;
    result ^= self.messageThread.hash;
    result ^= self.sentRecipientAddress.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingSentMessageTranscript *typedOther = (OWSOutgoingSentMessageTranscript *)other;
    if (self.isRecipientUpdate != typedOther.isRecipientUpdate) {
        return NO;
    }
    if (![NSObject isObject:self.message equalToObject:typedOther.message]) {
        return NO;
    }
    if (![NSObject isObject:self.messageThread equalToObject:typedOther.messageThread]) {
        return NO;
    }
    if (![NSObject isObject:self.sentRecipientAddress equalToObject:typedOther.sentRecipientAddress]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSOutgoingSentMessageTranscript *result = [super copyWithZone:zone];
    result->_isRecipientUpdate = self.isRecipientUpdate;
    result->_message = self.message;
    result->_messageThread = self.messageThread;
    result->_sentRecipientAddress = self.sentRecipientAddress;
    return result;
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageSentBuilder *sentBuilder = [SSKProtoSyncMessageSent builder];
    [sentBuilder setTimestamp:self.timestamp];
    [sentBuilder setDestinationE164:self.sentRecipientAddress.phoneNumber];
    if (BuildFlagsObjC.serviceIdStrings) {
        [sentBuilder setDestinationServiceID:self.sentRecipientAddress.serviceIdString];
    }
    if (BuildFlagsObjC.serviceIdBinaryConstantOverhead) {
        [sentBuilder setDestinationServiceIDBinary:self.sentRecipientAddress.serviceIdObjC.serviceIdBinary];
    }
    [sentBuilder setIsRecipientUpdate:self.isRecipientUpdate];

    if (![self prepareDataSyncMessageContentWithSentBuilder:sentBuilder tx:transaction]) {
        return nil;
    }

    [self prepareUnidentifiedStatusSyncMessageContentWithSentBuilder:sentBuilder tx:transaction];

    NSError *error;
    SSKProtoSyncMessageSent *_Nullable sentProto = [sentBuilder buildAndReturnError:&error];
    if (error || !sentProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setSent:sentProto];
    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:@[ self.message.uniqueId ]];
}

@end

NS_ASSUME_NONNULL_END
