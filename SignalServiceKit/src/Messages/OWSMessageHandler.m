//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSMessageHandler.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// used in log formatting
NSString *envelopeAddress(SSKProtoEnvelope *envelope)
{
    return [envelope formattedAddress];
}

@implementation OWSMessageHandler

+ (void)logInvalidEnvelope:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope != nil);

    if (!envelope.hasType) {
        OWSFailDebug(@"No type.");
        return;
    }
    switch (envelope.unwrappedType) {
        case SSKProtoEnvelopeTypeCiphertext:
        case SSKProtoEnvelopeTypePrekeyBundle:
        case SSKProtoEnvelopeTypeReceipt:
        case SSKProtoEnvelopeTypeUnidentifiedSender:
        case SSKProtoEnvelopeTypeSenderkeyMessage:
        case SSKProtoEnvelopeTypePlaintextContent:
            break;

        case SSKProtoEnvelopeTypeUnknown: {
            OWSFailDebug(@"Type unknown.");
            return;
        }

        case SSKProtoEnvelopeTypeKeyExchange: {
            // Unsupported
            OWSFailDebug(@"Key exchange.");
            return;
        }

        default: {
            // Shouldn't happen
            OWSFailDebug(@"Other type.");
            return;
        }
    }
}

+ (NSString *)descriptionForEnvelopeType:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope != nil);

    if (!envelope.hasType) {
        return @"Missing Type.";
    }
    switch (envelope.unwrappedType) {
        case SSKProtoEnvelopeTypeUnknown:
            // Shouldn't happen
            return @"Unknown";
        case SSKProtoEnvelopeTypeCiphertext:
            return @"SignalEncryptedMessage";
        case SSKProtoEnvelopeTypeKeyExchange:
            // Unsupported
            return @"KeyExchange";
        case SSKProtoEnvelopeTypePrekeyBundle:
            return @"PreKeyEncryptedMessage";
        case SSKProtoEnvelopeTypeReceipt:
            return @"DeliveryReceipt";
        case SSKProtoEnvelopeTypeUnidentifiedSender:
            return @"UnidentifiedSender";
        case SSKProtoEnvelopeTypeSenderkeyMessage:
            return @"SenderKey";
        case SSKProtoEnvelopeTypePlaintextContent:
            return @"PlaintextContent";
        default:
            // Shouldn't happen
            return @"Other";
    }
}

+ (NSString *)descriptionForEnvelope:(SSKProtoEnvelope *)envelope
{
    OWSAssertDebug(envelope != nil);

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@, timestamp: %llu, serverTimestamp: %llu, "
                                      @"serverGuid: %@, content.length: %lu />",
                     [self descriptionForEnvelopeType:envelope],
                     envelopeAddress(envelope),
                     envelope.timestamp,
                     envelope.serverTimestamp,
                     envelope.serverGuid,
                     (unsigned long)envelope.content.length];
}

- (NSString *)descriptionForEnvelope:(SSKProtoEnvelope *)envelope
{
    return [[self class] descriptionForEnvelope:envelope];
}


/**
 * We don't want to just log `content.description` because we'd potentially log message bodies for dataMesssages and
 * sync transcripts
 */
- (NSString *)descriptionForContent:(SSKProtoContent *)content
{
    return [content contentDescription];
}

/**
 * We don't want to just log `dataMessage.description` because we'd potentially log message contents
 */
- (NSString *)descriptionForDataMessage:(SSKProtoDataMessage *)dataMessage
{
    return [dataMessage contentDescription];
}

@end

NS_ASSUME_NONNULL_END
