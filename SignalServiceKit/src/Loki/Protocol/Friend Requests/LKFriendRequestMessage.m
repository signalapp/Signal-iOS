#import "LKFriendRequestMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "ProfileManagerProtocol.h"
#import "SignalRecipient.h"
#import "SSKEnvironment.h"
#import "TSThread.h"

#import <SessionServiceKit/SessionServiceKit-Swift.h>

@implementation LKFriendRequestMessage

#pragma mark Initialization
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(nullable TSThread *)thread body:(nullable NSString *)body {
    return [self initOutgoingMessageWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:@[] expiresInSeconds:0 expireStartedAt:0
        isVoiceMessage:false groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

#pragma mark Building
- (nullable id)prepareCustomContentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = [super prepareCustomContentBuilder:recipient];
    // Attach the pre key bundle for the contact in question
    PreKeyBundle *preKeyBundle = [OWSPrimaryStorage.sharedManager generatePreKeyBundleForContact:recipient.recipientId];
    SSKProtoPrekeyBundleMessageBuilder *preKeyBundleMessageBuilder = [SSKProtoPrekeyBundleMessage builderFromPreKeyBundle:preKeyBundle];
    NSError *error;
    SSKProtoPrekeyBundleMessage *preKeyBundleMessage = [preKeyBundleMessageBuilder buildAndReturnError:&error];
    if (error || preKeyBundleMessage == nil) {
        OWSFailDebug(@"Failed to build pre key bundle message for: %@ due to error: %@.", recipient.recipientId, error);
        return nil;
    } else {
         [contentBuilder setPrekeyBundleMessage:preKeyBundleMessage];
    }
    return contentBuilder;
}

#pragma mark Settings
- (uint)ttl { return (uint)[LKTTLUtilities getTTLFor:LKMessageTypeFriendRequest]; }
- (BOOL)shouldSyncTranscript { return self.thread.isNoteToSelf; }

@end
