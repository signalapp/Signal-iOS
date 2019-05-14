#import "OWSFriendRequestMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation OWSFriendRequestMessage

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
    
    PreKeyBundle *bundle = [OWSPrimaryStorage.sharedManager generatePreKeyBundleForContact:recipient.recipientId];
    SSKProtoPrekeyBundleMessageBuilder *preKeyBuilder = [SSKProtoPrekeyBundleMessage builderFromPreKeyBundle:bundle];
    
    // Build the prekey bundle message
    NSError *error;
    SSKProtoPrekeyBundleMessage *_Nullable message = [preKeyBuilder buildAndReturnError:&error];
    if (error || !message) {
        OWSFailDebug(@"Failed to build preKeyBundle for %@: %@", recipient.recipientId, error);
    } else {
         [contentBuilder setPrekeyBundleMessage:message];
    }
    
    return contentBuilder;
}

@end
