#import <Foundation/Foundation.h>
#import "CallController.h"
#import "HttpManager.h"
#import "ResponderSessionDescriptor.h"

/**
 *
 * CallConnectUtil_Responder is a utility class that deals with the details of responding to a call:
 * - Contacting the described signaling server
 * - Signalling busy or ringing
 * - Forwarding later signals like 'hangup'
 * - Contacting the described relay server
 * - Starting the zrtp handshake
 * - etc
 *
 **/
@interface CallConnectUtil_Responder : NSObject

/// Result has type Future(CallConnectResult)
+ (TOCFuture *)asyncConnectToIncomingCallWithSessionDescriptor:(ResponderSessionDescriptor *)sessionDescriptor
                                             andCallController:(CallController *)callController;

/// Result has type Future(HttpResponse)
+ (TOCFuture *)asyncSignalTooBusyToAnswerCallWithSessionDescriptor:(ResponderSessionDescriptor *)sessionDescriptor;

@end
