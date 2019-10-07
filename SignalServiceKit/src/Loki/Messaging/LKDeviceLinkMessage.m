#import "LKDeviceLinkMessage.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+Loki.h"
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
- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient
{
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
       
    // If it's a linking request then we should send a prekey bundle
    if (self.masterSignature == nil) {
        PreKeyBundle *bundle = [OWSPrimaryStorage.sharedManager generatePreKeyBundleForContact:recipient.recipientId];
        SSKProtoPrekeyBundleMessageBuilder *preKeyBuilder = [SSKProtoPrekeyBundleMessage builderFromPreKeyBundle:bundle];

        // Build the prekey bundle message
        NSError *error;
        SSKProtoPrekeyBundleMessage *_Nullable message = [preKeyBuilder buildAndReturnError:&error];
        if (error || !message) {
            OWSFailDebug(@"Failed to build pre key bundle for %@: %@", recipient.recipientId, error);
            return nil;
        } else {
            [contentBuilder setPrekeyBundleMessage:message];
        }
    }
    
    // Device link message
    NSError *error;
    SSKProtoLokiDeviceLinkMessageBuilder *deviceLinkMessageBuilder = [SSKProtoLokiDeviceLinkMessage builder];
    [deviceLinkMessageBuilder setMasterHexEncodedPublicKey:self.masterHexEncodedPublicKey];
    [deviceLinkMessageBuilder setSlaveHexEncodedPublicKey:self.slaveHexEncodedPublicKey];
    if (self.masterSignature != nil) { [deviceLinkMessageBuilder setMasterSignature:self.masterSignature]; }
    [deviceLinkMessageBuilder setSlaveSignature:self.slaveSignature];
    SSKProtoLokiDeviceLinkMessage *deviceLinkMessage = [deviceLinkMessageBuilder buildAndReturnError:&error];
    if (error || deviceLinkMessage == nil) {
        OWSFailDebug(@"Failed to build device link message due to error: %@.", error);
        return nil;
    } else {
        [contentBuilder setLokiDeviceLinkMessage:deviceLinkMessage];
    }
    
    return contentBuilder;
}

#pragma mark Settings
- (uint)ttl { return 2 * kMinuteInMs; }
- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
