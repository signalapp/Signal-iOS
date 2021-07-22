//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingResendResponse.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSOutgoingResendResponse ()
@property (strong, nonatomic, readonly) SignalServiceAddress *address;
@property (assign, nonatomic, readonly) int64_t deviceId;
@property (strong, nonatomic, readonly) NSDate *originalSentDate;
@property (assign, nonatomic, readonly) BOOL didPerformSessionReset;
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

    NSDate *originalSentDate = [NSDate ows_dateWithMillisecondsSince1970:failedTimestamp];
    Payload *payloadRecord = [MessageSendLog fetchPayloadWithAddress:address
                                                            deviceId:deviceId
                                                           timestamp:originalSentDate
                                                         transaction:transaction];

    if (!payloadRecord && !didPerformSessionReset) {
        OWSLogInfo(@"No stored payload record and no session reset. Declining to send response.");
        return nil;
    }

    if (payloadRecord) {
        OWSLogInfo(@"Found an MSL record for resend request: %@", originalSentDate);

        NSString *originalThreadId = payloadRecord.uniqueThreadId;
        TSThread *originalThread = [TSThread anyFetchWithUniqueId:originalThreadId transaction:transaction];
        if (originalThread.isGroupThread) {
            TSGroupThread *groupThread = (TSGroupThread *)originalThread;
            OWSLogDebug(@"Resetting delivery record in response to failed send to %@ in %@", address, originalThreadId);
            [self.senderKeyStore resetSenderKeyDeliveryRecordFor:groupThread address:address writeTx:transaction];
        }
    } else {
        OWSLogInfo(@"Did not find an MSL record for resend request: %@", originalSentDate);
    }

    TSThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address transaction:transaction];
    TSOutgoingMessageBuilder *builder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    if (payloadRecord.sentTimestamp) {
        builder.timestamp = payloadRecord.sentTimestamp.ows_millisecondsSince1970;
    }

    self = [super initOutgoingMessageWithBuilder:builder];
    if (self) {
        _address = address;
        _deviceId = deviceId;
        _originalSentDate = originalSentDate;
        _didPerformSessionReset = didPerformSessionReset;
    }
    return self;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug([self.recipientAddresses containsObject:self.address]);
    OWSAssertDebug(self.recipientAddresses.count == 1);
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    // We should re-fetch the payload to be certain that it has not been deleted.
    Payload *payloadRecord = [MessageSendLog fetchPayloadWithAddress:self.address
                                                            deviceId:self.deviceId
                                                           timestamp:self.originalSentDate
                                                         transaction:transaction];

    NSError *error = nil;
    SSKProtoContentBuilder *contentBuilder = nil;

    if (payloadRecord.plaintextContent) {
        contentBuilder = [[[SSKProtoContent alloc] initWithSerializedData:payloadRecord.plaintextContent
                                                                    error:&error] asBuilder];
        if (!contentBuilder || error) {
            OWSFailDebug(@"Failed to rebuild MSL proto: %@", error);
        } else {
            NSString *originalThreadId = payloadRecord.uniqueThreadId;
            TSThread *originalThread = [TSThread anyFetchWithUniqueId:originalThreadId transaction:transaction];
            if (originalThread.isGroupThread && [originalThread.recipientAddresses containsObject:self.address]) {
                __unused TSGroupThread *groupThread = (TSGroupThread *)originalThread;
                // TODO: Append current sender key to proto
            }
        }
    }

    if (!contentBuilder && self.didPerformSessionReset) {
        // Outgoing messages set their timestamp in init.
        // If this is a resent message, it should have the timestamp of the original message
        // If this is a null message signaling session reset, it should have the current time.
        //
        // If an MSL entry exists during -init, but then the entry is deleted by the time
        // this message can be sent: We may send a null message with the old timestamp. The
        // receiver would interpret this to mean that the orignal message *was* a null message.
        // TODO: Can we update the timestamp retroactively?
        SSKProtoNullMessageBuilder *nullMessageBuilder = [SSKProtoNullMessage builder];
        SSKProtoNullMessage *nullMessage = [nullMessageBuilder buildAndReturnError:&error];

        if (!nullMessage) {
            OWSFailDebug(@"Failed to build null message: %@", error);
            return nil;
        }

        contentBuilder = [SSKProtoContent builder];
        [contentBuilder setNullMessage:nullMessage];
    }

    NSData *plaintextMessage = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (!plaintextMessage || error) {
        OWSFailDebug(@"Failed to build plaintext message: %@", error);
    }
    return plaintextMessage;
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

@end
