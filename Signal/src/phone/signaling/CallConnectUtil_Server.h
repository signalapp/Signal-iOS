#import <Foundation/Foundation.h>
#import "CallController.h"
#import "InitiatorSessionDescriptor.h"
#import "ResponderSessionDescriptor.h"

/**
 *
 * CallConnectUtil_Server is a utility class exposing methods related to connecting to relay/signaling servers.
 *
 **/
@interface CallConnectUtil_Server : NSObject

/// Result has type Future(HttpManager)
+(Future*) asyncConnectToDefaultSignalingServerUntilCancelled:(id<CancelToken>)untilCancelledToken;

/// Result has type Future(HttpManager)
+(Future*) asyncConnectToSignalingServerNamed:(NSString*)name
                               untilCancelled:(id<CancelToken>)untilCancelledToken;

/// Result has type Future(CallConnectResult)
+(Future*) asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:(ResponderSessionDescriptor*)session
                                                       withCallController:(CallController*)callController;

/// Result has type Future(CallConnectResult)
+(Future*) asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:(InitiatorSessionDescriptor*)session
                                                       withCallController:(CallController*)callController
                                                        andInteropOptions:(NSArray*)interopOptions;

@end
