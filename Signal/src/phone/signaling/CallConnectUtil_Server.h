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
+ (TOCFuture *)asyncConnectToDefaultSignalingServerUntilCancelled:(TOCCancelToken *)untilCancelledToken;

/// Result has type Future(HttpManager)
+ (TOCFuture *)asyncConnectToSignalingServerNamed:(NSString *)name untilCancelled:(TOCCancelToken *)untilCancelledToken;

/// Result has type Future(CallConnectResult)
+ (TOCFuture *)asyncConnectCallOverRelayDescribedInResponderSessionDescriptor:(ResponderSessionDescriptor *)session
                                                           withCallController:(CallController *)callController;

/// Result has type Future(CallConnectResult)
+ (TOCFuture *)asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:(InitiatorSessionDescriptor *)session
                                                           withCallController:(CallController *)callController
                                                            andInteropOptions:(NSArray *)interopOptions;

@end
