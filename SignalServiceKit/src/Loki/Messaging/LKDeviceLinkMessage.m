#import "LKDeviceLinkMessage.h"
#import "OWSIdentityManager.h"
#import "SignalRecipient.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKDeviceLinkMessage

#pragma mark Convenience
- (LKDeviceLinkMessageKind)kind {
    if (self.masterSignature != nil) {
        return LKDeviceLinkMessageKindAuthorization;
    } else {
        return LKDeviceLinkMessageKindRequest;
    }
}

#pragma mark Initialization
- (instancetype)initInThread:(TSThread *)thread masterHexEncodedPublicKey:(NSString *)masterHexEncodedPublicKey slaveHexEncodedPublicKey:(NSString *)slaveHexEncodedPublicKey masterSignature:(NSData *)masterSignature slaveSignature:(NSData *)slaveSignature {
    self = [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
    if (self) {
        _masterHexEncodedPublicKey = masterHexEncodedPublicKey;
        _slaveHexEncodedPublicKey = slaveHexEncodedPublicKey;
        _masterSignature = masterSignature;
        _slaveSignature = slaveSignature;
    }
    return self;
}

#pragma mark Building
- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    // Prepare
    SSKProtoContentBuilder *contentBuilder = [self contentBuilder:recipient];
    NSError *error;
    // Data message
    SSKProtoDataMessage *_Nullable dataMessage = [self buildDataMessage:recipient.recipientId];
    if (!dataMessage) {
        OWSFailDebug(@"Failed to build data message.");
        return nil;
    }
    [contentBuilder setDataMessage:dataMessage];
    // Device link message
    SSKProtoLokiDeviceLinkMessageBuilder *deviceLinkMessageBuilder = [SSKProtoLokiDeviceLinkMessage builder];
    [deviceLinkMessageBuilder setMasterHexEncodedPublicKey:self.masterHexEncodedPublicKey];
    [deviceLinkMessageBuilder setSlaveHexEncodedPublicKey:self.slaveHexEncodedPublicKey];
    if (self.masterSignature != nil) { [deviceLinkMessageBuilder setMasterSignature:self.masterSignature]; }
    [deviceLinkMessageBuilder setSlaveSignature:self.slaveSignature];
    SSKProtoLokiDeviceLinkMessage *deviceLinkMessage = [deviceLinkMessageBuilder buildAndReturnError:&error];
    if (error || deviceLinkMessage == nil) {
        OWSFailDebug(@"Failed to build device link message due to error: %@.", error);
        return nil;
    }
    [contentBuilder setLokiDeviceLinkMessage:deviceLinkMessage];
    // Serialize
    NSData *_Nullable contentAsData = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error || !contentAsData) {
        OWSFailDebug(@"Failed to build serialized message content due to error: %@.", error);
        return nil;
    }
    // Return
    return contentAsData;
}

#pragma mark Settings
- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
