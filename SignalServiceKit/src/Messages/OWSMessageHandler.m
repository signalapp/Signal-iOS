//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// used in log formatting
NSString *envelopeAddress(SSKProtoEnvelope *envelope)
{
    return [NSString stringWithFormat:@"%@.%d", envelope.source, (unsigned int)envelope.sourceDevice];
}

@implementation OWSMessageHandler

- (NSString *)descriptionForEnvelopeType:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope != nil);

    switch (envelope.type) {
        case SSKProtoEnvelopeTypeReceipt:
            return @"DeliveryReceipt";
        case SSKProtoEnvelopeTypeUnknown:
            // Shouldn't happen
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeUnknown]);
            return @"Unknown";
        case SSKProtoEnvelopeTypeCiphertext:
            return @"SignalEncryptedMessage";
        case SSKProtoEnvelopeTypeKeyExchange:
            // Unsupported
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeKeyExchange]);
            return @"KeyExchange";
        case SSKProtoEnvelopeTypePrekeyBundle:
            return @"PreKeyEncryptedMessage";
        default:
            // Shouldn't happen
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeOther]);
            return @"Other";
    }
}

- (NSString *)descriptionForEnvelope:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope != nil);

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@, timestamp: %llu content.length: %lu />",
                     [self descriptionForEnvelopeType:envelope],
                     envelopeAddress(envelope),
                     envelope.timestamp,
                     (unsigned long)envelope.content.length];
}

/**
 * We don't want to just log `content.description` because we'd potentially log message bodies for dataMesssages and
 * sync transcripts
 */
- (NSString *)descriptionForContent:(SSKProtoContent *)content
{
    if (content.syncMessage) {
        return [NSString stringWithFormat:@"<SyncMessage: %@ />", [self descriptionForSyncMessage:content.syncMessage]];
    } else if (content.dataMessage) {
        return [NSString stringWithFormat:@"<DataMessage: %@ />", [self descriptionForDataMessage:content.dataMessage]];
    } else if (content.callMessage) {
        NSString *callMessageDescription = [self descriptionForCallMessage:content.callMessage];
        return [NSString stringWithFormat:@"<CallMessage %@ />", callMessageDescription];
    } else if (content.nullMessage) {
        return [NSString stringWithFormat:@"<NullMessage: %@ />", content.nullMessage];
    } else if (content.receiptMessage) {
        return [NSString stringWithFormat:@"<ReceiptMessage: %@ />", content.receiptMessage];
    } else {
        // Don't fire an analytics event; if we ever add a new content type, we'd generate a ton of
        // analytics traffic.
        OWSFailDebug(@"Unknown content type.");
        return @"UnknownContent";
    }
}

- (NSString *)descriptionForCallMessage:(SSKProtoCallMessage *)callMessage
{
    NSString *messageType;
    UInt64 callId;

    if (callMessage.offer) {
        messageType = @"Offer";
        callId = callMessage.offer.id;
    } else if (callMessage.busy) {
        messageType = @"Busy";
        callId = callMessage.busy.id;
    } else if (callMessage.answer) {
        messageType = @"Answer";
        callId = callMessage.answer.id;
    } else if (callMessage.hangup) {
        messageType = @"Hangup";
        callId = callMessage.hangup.id;
    } else if (callMessage.iceUpdate.count > 0) {
        messageType = [NSString stringWithFormat:@"Ice Updates (%lu)", (unsigned long)callMessage.iceUpdate.count];
        callId = callMessage.iceUpdate.firstObject.id;
    } else {
        OWSFailDebug(@"failure: unexpected call message type: %@", callMessage);
        messageType = @"Unknown";
        callId = 0;
    }

    return [NSString stringWithFormat:@"type: %@, id: %llu", messageType, callId];
}

/**
 * We don't want to just log `dataMessage.description` because we'd potentially log message contents
 */
- (NSString *)descriptionForDataMessage:(SSKProtoDataMessage *)dataMessage
{
    NSMutableString *description = [NSMutableString new];

    if (dataMessage.group) {
        [description appendString:@"(Group:YES) "];
    }

    if ((dataMessage.flags & SSKProtoDataMessageFlagsEndSession) != 0) {
        [description appendString:@"EndSession"];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsExpirationTimerUpdate) != 0) {
        [description appendString:@"ExpirationTimerUpdate"];
    } else if ((dataMessage.flags & SSKProtoDataMessageFlagsProfileKeyUpdate) != 0) {
        [description appendString:@"ProfileKey"];
    } else if (dataMessage.attachments.count > 0) {
        [description appendString:@"MessageWithAttachment"];
    } else {
        [description appendString:@"Plain"];
    }

    return [NSString stringWithFormat:@"<%@ />", description];
}

/**
 * We don't want to just log `syncMessage.description` because we'd potentially log message contents in sent transcripts
 */
- (NSString *)descriptionForSyncMessage:(SSKProtoSyncMessage *)syncMessage
{
    NSMutableString *description = [NSMutableString new];
    if (syncMessage.sent) {
        [description appendString:@"SentTranscript"];
    } else if (syncMessage.request) {
        if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeContacts) {
            [description appendString:@"ContactRequest"];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeGroups) {
            [description appendString:@"GroupRequest"];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeBlocked) {
            [description appendString:@"BlockedRequest"];
        } else if (syncMessage.request.type == SSKProtoSyncMessageRequestTypeConfiguration) {
            [description appendString:@"ConfigurationRequest"];
        } else {
            OWSFailDebug(@"Unknown sync message request type");
            [description appendString:@"UnknownRequest"];
        }
    } else if (syncMessage.blocked) {
        [description appendString:@"Blocked"];
    } else if (syncMessage.read.count > 0) {
        [description appendString:@"ReadReceipt"];
    } else if (syncMessage.verified) {
        NSString *verifiedString =
            [NSString stringWithFormat:@"Verification for: %@", syncMessage.verified.destination];
        [description appendString:verifiedString];
    } else {
        OWSFailDebug(@"Unknown sync message type");
        [description appendString:@"Unknown"];
    }

    return description;
}

@end

NS_ASSUME_NONNULL_END
