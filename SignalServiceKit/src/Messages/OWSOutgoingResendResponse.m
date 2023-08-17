//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingResendResponse.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSOutgoingResendResponse ()
@property (nonatomic, readonly, nullable) NSData *originalMessagePlaintext;
@property (nonatomic, readonly, nullable) NSString *originalThreadId;
@property (nonatomic, readonly, nullable) NSData *originalGroupId;
@property (nonatomic, readonly) SealedSenderContentHint derivedContentHint;

@property (nonatomic) BOOL didAppendSKDM;
@end

@implementation OWSOutgoingResendResponse

- (instancetype)initWithOutgoingMessageBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                      originalMessagePlaintext:(nullable NSData *)originalMessagePlaintext
                              originalThreadId:(nullable NSString *)originalThreadId
                               originalGroupId:(nullable NSData *)originalGroupId
                            derivedContentHint:(NSInteger)derivedContentHint
                                   transaction:(SDSAnyWriteTransaction *)transaction
{
    self = [super initOutgoingMessageWithBuilder:outgoingMessageBuilder transaction:transaction];
    if (self) {
        _originalMessagePlaintext = [originalMessagePlaintext copy];
        _originalThreadId = [originalThreadId copy];
        _derivedContentHint = (SealedSenderContentHint)derivedContentHint;
        _originalGroupId = [originalGroupId copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(self.recipientAddresses.count == 1);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    SignalServiceAddress *recipient = self.recipientAddresses.firstObject;

    SSKProtoContentBuilder *_Nullable contentBuilder = nil;

    if (self.originalMessagePlaintext) {
        contentBuilder = [self resentProtoBuilderFromPlaintext:self.originalMessagePlaintext];
    }
    if (!contentBuilder) {
        contentBuilder = [self nullMessageProtoBuilder];
    }
    if (!contentBuilder) {
        OWSFailDebug(@"Failed to construct content builder");
        return nil;
    }

    TSThread *originalThread = nil;
    if (self.originalThreadId) {
        originalThread = [TSThread anyFetchWithUniqueId:self.originalThreadId transaction:transaction];
    }
    if (originalThread.usesSenderKey &&
        [[originalThread recipientAddressesWithTransaction:transaction] containsObject:recipient]) {
        NSData *skdmBytes = [self.senderKeyStore skdmBytesForThread:originalThread tx:transaction];
        [contentBuilder setSenderKeyDistributionMessage:skdmBytes];

        self.didAppendSKDM = (skdmBytes != nil);
    }

    NSError *_Nullable error = nil;
    NSData *plaintextMessage = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (!plaintextMessage || error) {
        OWSFailDebug(@"Failed to build plaintext message: %@", error);
        return nil;
    } else {
        return plaintextMessage;
    }
}

- (void)updateWithSentRecipient:(ServiceIdObjC *)serviceId
                    wasSentByUD:(BOOL)wasSentByUD
                    transaction:(SDSAnyWriteTransaction *)transaction
{
    [super updateWithSentRecipient:serviceId wasSentByUD:wasSentByUD transaction:transaction];

    // Message was sent! Re-mark the recipient as having been sent an SKDM
    if (self.didAppendSKDM) {
        TSThread *originalThread = nil;
        if (self.originalThreadId) {
            originalThread = [TSThread anyFetchWithUniqueId:self.originalThreadId transaction:transaction];
        }
        if (originalThread.usesSenderKey) {
            NSError *error = nil;
            [self.senderKeyStore recordSenderKeySentFor:originalThread
                                                     to:serviceId
                                              timestamp:self.timestamp
                                                writeTx:transaction
                                                  error:&error];
            if (error) {
                OWSFailDebug(@"Unexpected error when updating sender key store: %@", error);
            }
        } else {
            OWSFailDebug(@"Appended an SKDM but not a sender key thread. Not expected.");
        }
    }
}

- (BOOL)shouldRecordSendLog
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (SealedSenderContentHint)contentHint
{
    return self.derivedContentHint;
}

- (nullable NSData *)envelopeGroupIdWithTransaction:(__unused SDSAnyReadTransaction *)transaction
{
    return self.originalGroupId;
}

- (nullable SSKProtoContentBuilder *)resentProtoBuilderFromPlaintext:(NSData *)plaintext
{
    NSError *_Nullable error = nil;
    SSKProtoContent *_Nullable content = [[SSKProtoContent alloc] initWithSerializedData:plaintext error:&error];

    if (!content || error) {
        OWSFailDebug(@"Failed to build resent content %@", error);
        return nil;
    } else {
        return [content asBuilder];
    }
}

- (nullable SSKProtoContentBuilder *)nullMessageProtoBuilder
{
    NSError *_Nullable error = nil;
    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];

    SSKProtoNullMessageBuilder *nullMessageBuilder = [SSKProtoNullMessage builder];
    SSKProtoNullMessage *nullMessage = [nullMessageBuilder buildAndReturnError:&error];
    [contentBuilder setNullMessage:nullMessage];

    if (!contentBuilder || error) {
        OWSFailDebug(@"Failed to build content builder %@", error);
        return nil;
    } else {
        return contentBuilder;
    }
}

@end
