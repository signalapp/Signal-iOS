#import "LKDeviceLinkMessage.h"
#import "OWSIdentityManager.h"
#import "SignalRecipient.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKDeviceLinkMessage

- (instancetype)initInThread:(TSThread *)thread masterHexEncodedPublicKey:(NSString *)masterHexEncodedPublicKey slaveHexEncodedPublicKey:(NSString *)slaveHexEncodedPublicKey
    masterSignature:(NSData *)masterSignature slaveSignature:(NSData *)slaveSignature kind:(LKDeviceLinkMessageKind)kind {
    self = [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
    if (self) {
        _masterHexEncodedPublicKey = masterHexEncodedPublicKey;
        _slaveHexEncodedPublicKey = slaveHexEncodedPublicKey;
        _masterSignature = masterSignature;
        _slaveSignature = slaveSignature;
        _kind = kind;
    }
    return self;
}

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoLokiDeviceLinkMessageBuilder *deviceLinkMessageBuilder = [SSKProtoLokiDeviceLinkMessage builder];
    [deviceLinkMessageBuilder setMasterHexEncodedPublicKey:self.masterHexEncodedPublicKey];
    [deviceLinkMessageBuilder setSlaveHexEncodedPublicKey:self.slaveHexEncodedPublicKey];
    if (self.masterSignature != nil) { [deviceLinkMessageBuilder setMasterSignature:self.masterSignature]; }
    [deviceLinkMessageBuilder setSlaveSignature:self.slaveSignature];
    switch (self.kind) {
        case LKDeviceLinkMessageKindRequest:
            [deviceLinkMessageBuilder setType:SSKProtoLokiDeviceLinkMessageTypeRequest];
            break;
        case LKDeviceLinkMessageKindAuthorization:
            [deviceLinkMessageBuilder setType:SSKProtoLokiDeviceLinkMessageTypeAuthorization];
            break;
        case LKDeviceLinkMessageKindRevocation:
            [deviceLinkMessageBuilder setType:SSKProtoLokiDeviceLinkMessageTypeRevocation];
            break;
    }
    NSError *error;
    SSKProtoLokiDeviceLinkMessage *deviceLinkMessage = [deviceLinkMessageBuilder buildAndReturnError:&error];
    if (error || deviceLinkMessage == nil) {
        OWSFailDebug(@"Failed to build device link message due to error: %@", error);
    }
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
    [contentBuilder setLokiDeviceLinkMessage:deviceLinkMessage];
    return contentBuilder;
}

- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
