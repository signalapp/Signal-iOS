#import "OWSFriendRequestMessage.h"

@implementation OWSFriendRequestMessage

- (SSKProtoContentBuilder *)contentBuilder {
    SSKProtoContentBuilder *contentBuilder = super.contentBuilder;
    
    // TODO: Attach pre-key bundle here
    
    return contentBuilder;
}

@end
