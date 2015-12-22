#import <Foundation/Foundation.h>
#import "CallController.h"
#import "HttpManager.h"
#import "InitiatorSessionDescriptor.h"

/**
 *
 * CallConnectUtil_Initiator is a utility class that deals with the details of initiating a call:
 * - Contacting the default signaling server
 * - Asking for a session descriptor to call the other number
 * - Forwarding later signals like 'ringing' and 'hangup'
 * - Contacting the relay server from the descriptor
 * - Starting the zrtp handshake
 * - etc
 *
 **/
@interface CallConnectUtil_Initiator : NSObject

/// Result has type Future*(CallConnectResult)
+ (TOCFuture *)asyncConnectCallToRemoteNumber:(PhoneNumber *)remoteNumber
                           withCallController:(CallController *)callController;

@end
