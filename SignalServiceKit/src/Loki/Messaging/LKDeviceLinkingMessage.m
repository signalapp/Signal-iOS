#import "LKDeviceLinkingMessage.h"
#import "OWSIdentityManager.h"
#import "SignalRecipient.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKDeviceLinkingMessage

- (instancetype)initInThread:(nullable TSThread *)thread {
    return [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
    // When authorizing a device link, the master device signs the slave device's public key. When requesting
    // a device link, the slave device signs the master device's public key.
    SSKProtoLokiDeviceLinkingMessageBuilder *deviceLinkingMessageBuilder = [SSKProtoLokiDeviceLinkingMessage builder];
    NSString *masterHexEncodedPublicKey = recipient.recipientId;
    NSData *masterPublicKey = [NSData dataFromHexString:masterHexEncodedPublicKey];
    [deviceLinkingMessageBuilder setMasterHexEncodedPublicKey:masterHexEncodedPublicKey];
    ECKeyPair *slaveKeyPair = OWSIdentityManager.sharedManager.identityKeyPair;
    NSString *slaveHexEncodedPublicKey = slaveKeyPair.hexEncodedPublicKey;
    [deviceLinkingMessageBuilder setSlaveHexEncodedPublicKey:slaveHexEncodedPublicKey];
    NSData *slaveSignature = [Ed25519 sign:masterPublicKey withKeyPair:slaveKeyPair error:nil];
    [deviceLinkingMessageBuilder setSlaveSignature:slaveSignature];
    NSError *error;
    SSKProtoLokiDeviceLinkingMessage *deviceLinkingMessage = [deviceLinkingMessageBuilder buildAndReturnError:&error];
    if (error || deviceLinkingMessage == nil) {
        OWSFailDebug(@"Failed to build device linking message for: %@ due to error: %@", masterHexEncodedPublicKey, error);
    }
    [contentBuilder setLokiDeviceLinkingMessage:deviceLinkingMessage];
    return contentBuilder;
}

- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
