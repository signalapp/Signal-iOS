#import "LKDeviceLinkingMessage.h"
#import "OWSIdentityManager.h"
#import "SignalRecipient.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKDeviceLinkingMessage

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

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoLokiDeviceLinkingMessageBuilder *deviceLinkingMessageBuilder = [SSKProtoLokiDeviceLinkingMessage builder];
    [deviceLinkingMessageBuilder setMasterHexEncodedPublicKey:self.masterHexEncodedPublicKey];
    [deviceLinkingMessageBuilder setSlaveHexEncodedPublicKey:self.slaveHexEncodedPublicKey];
    if (self.masterSignature != nil) { [deviceLinkingMessageBuilder setMasterSignature:self.masterSignature]; }
    [deviceLinkingMessageBuilder setSlaveSignature:self.slaveSignature];
    NSError *error;
    SSKProtoLokiDeviceLinkingMessage *deviceLinkingMessage = [deviceLinkingMessageBuilder buildAndReturnError:&error];
    if (error || deviceLinkingMessage == nil) {
        OWSFailDebug(@"Failed to build device linking message for: %@ due to error: %@", self.masterHexEncodedPublicKey, error);
    }
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
    [contentBuilder setLokiDeviceLinkingMessage:deviceLinkingMessage];
    return contentBuilder;
}

- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
