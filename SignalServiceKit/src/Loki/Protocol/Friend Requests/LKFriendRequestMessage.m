#import "LKFriendRequestMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "ProfileManagerProtocol.h"
#import "SignalRecipient.h"
#import "SSKEnvironment.h"
#import "TSThread.h"

#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKFriendRequestMessage

#pragma mark Building
- (SSKProtoContentBuilder *)prepareCustomContentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = SSKProtoContent.builder;
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
