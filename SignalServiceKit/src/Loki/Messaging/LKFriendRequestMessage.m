#import "LKFriendRequestMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKFriendRequestMessage

- (SSKProtoContentBuilder *)prepareCustomContentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = SSKProtoContent.builder;
    
    PreKeyBundle *bundle = [OWSPrimaryStorage.sharedManager generatePreKeyBundleForContact:recipient.recipientId];
    SSKProtoPrekeyBundleMessageBuilder *preKeyBuilder = [SSKProtoPrekeyBundleMessage builderFromPreKeyBundle:bundle];
    
    // Build the pre key bundle message
    NSError *error;
    SSKProtoPrekeyBundleMessage *_Nullable message = [preKeyBuilder buildAndReturnError:&error];
    if (error || !message) {
        OWSFailDebug(@"Failed to build pre key bundle for: %@ due to error: %@.", recipient.recipientId, error);
    } else {
         [contentBuilder setPrekeyBundleMessage:message];
    }
    
    return contentBuilder;
}

- (uint)ttl { return 4 * kDayInMs; }

@end
