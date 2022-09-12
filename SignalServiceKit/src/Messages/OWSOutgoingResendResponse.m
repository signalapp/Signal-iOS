//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingResendResponse.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSOutgoingResendResponse ()
@property (nonatomic, readonly, nullable) NSData *originalMessagePlaintext;
@property (nonatomic, readonly, nullable) NSString *originalThreadId;
@property (nonatomic, readonly, nullable) NSData *originalGroupId;

@property (nonatomic) BOOL didAppendSKDM;
@end

@implementation OWSOutgoingResendResponse

- (nullable instancetype)initWithAddress:(SignalServiceAddress *)address
                                deviceId:(int64_t)deviceId
                         failedTimestamp:(int64_t)failedTimestamp
                         didResetSession:(BOOL)didPerformSessionReset
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);
    TSThread *targetThread = [TSContactThread getOrCreateThreadWithContactAddress:address transaction:transaction];
    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:targetThread];

    Payload *_Nullable payloadRecord = [MessageSendLog fetchPayloadWithAddress:address
                                                                      deviceId:deviceId
                                                                     timestamp:failedTimestamp
                                                                   transaction:transaction];

    TSThread *_Nullable originalThread = nil;
    if (payloadRecord) {
        OWSLogInfo(@"Found an MSL record for resend request: %lli", failedTimestamp);
        originalThread = [TSThread anyFetchWithUniqueId:payloadRecord.uniqueThreadId transaction:transaction];

        // We should inherit the timestamp of the failed message. This allows the recipient of this message
        // to correlate the resend response with the original failed message.
        builder.timestamp = payloadRecord.sentTimestamp;
        // We also want to reset the delivery record for the failing address if this was a sender key group
        // This will be re-marked as delivered on success if we included an SKDM in the resend response
        [self resetSenderKeyDeliveryRecordIfNecessaryForThreadId:payloadRecord.uniqueThreadId
                                                         address:address
                                                     transaction:transaction];
    } else if (didPerformSessionReset) {
        OWSLogInfo(
            @"Failed to find MSL record for resend request: %lli. Will reply with Null message", failedTimestamp);
    } else {
        OWSLogInfo(@"Failed to find MSL record for resend request: %lli. Declining to respond.", failedTimestamp);
        return nil;
    }

    self = [super initOutgoingMessageWithBuilder:builder transaction:transaction];
    if (self) {
        _originalMessagePlaintext = payloadRecord.plaintextContent;
        _originalThreadId = payloadRecord.uniqueThreadId;

        if ([originalThread isKindOfClass:[TSGroupThread class]]) {
            _originalGroupId = ((TSGroupThread *)originalThread).groupId;
        }
    }
    return self;
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
        NSData *skdmBytes = [self.senderKeyStore skdmBytesForThread:originalThread writeTx:transaction];
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

- (void)updateWithSentRecipient:(SignalServiceAddress *)recipientAddress
                    wasSentByUD:(BOOL)wasSentByUD
                    transaction:(SDSAnyWriteTransaction *)transaction
{
    [super updateWithSentRecipient:recipientAddress wasSentByUD:wasSentByUD transaction:transaction];

    // Message was sent! Re-mark the recipient as having been sent an SKDM
    if (self.didAppendSKDM) {
        TSThread *originalThread = nil;
        if (self.originalThreadId) {
            originalThread = [TSThread anyFetchWithUniqueId:self.originalThreadId transaction:transaction];
        }
        if (originalThread.usesSenderKey) {
            NSError *error = nil;
            [self.senderKeyStore recordSenderKeySentFor:originalThread
                                                     to:recipientAddress
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
    return SealedSenderContentHintDefault;
}

- (nullable NSData *)envelopeGroupIdWithTransaction:(__unused SDSAnyReadTransaction *)transaction
{
    return self.originalGroupId;
}

- (void)resetSenderKeyDeliveryRecordIfNecessaryForThreadId:(NSString *)threadId
                                                   address:(SignalServiceAddress *)address
                                               transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(threadId);
    OWSAssertDebug(address);
    OWSAssertDebug(transaction);

    TSThread *originalThread = [TSThread anyFetchWithUniqueId:threadId transaction:transaction];
    if (originalThread.isGroupThread) {
        // Only group threads support sender key
        TSGroupThread *groupThread = (TSGroupThread *)originalThread;
        OWSLogDebug(@"Resetting delivery record in response to failed send to %@ in %@", address, threadId);
        [self.senderKeyStore resetSenderKeyDeliveryRecordFor:groupThread address:address writeTx:transaction];
    }
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
