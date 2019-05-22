#import "LKFriendRequestMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKFriendRequestMessage

- (BOOL)isFriendRequest { return YES; }

- (uint)ttl {
    // Friend requests should stay for the longest on the storage server
    return 4 * kDayInterval;
}

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
