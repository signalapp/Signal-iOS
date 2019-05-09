#import "OWSFriendRequestMessage.h"

@implementation OWSFriendRequestMessage

- (SSKProtoContentBuilder *)contentBuilder {
    SSKProtoContentBuilder *builder = [super contentBuilder];
    
    // TODO: Attach pre-key bundle here
    
    return builder;
}

@end
