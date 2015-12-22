#import <Foundation/Foundation.h>
#import "CallConnectResult.h"
#import "CallController.h"
#import "ResponderSessionDescriptor.h"

/**
 *
 * CallConnectUtil is a utility class containing methods related to connecting calls.
 *
 * Its implementation is actually split over more specific utility classes:
 * - CallConnectUtil_Initiator
 * - CallConnectUtil_Responder
 * - CallConnectUtil_Server
 *
 **/
@interface CallConnectUtil : NSObject

/// Result has type Future(CallConnectResult)
+ (TOCFuture *)asyncInitiateCallToRemoteNumber:(PhoneNumber *)remoteNumber
                             andCallController:(CallController *)callController;

/// Result has type Future(CallConnectResult)
+ (TOCFuture *)asyncRespondToCallWithSessionDescriptor:(ResponderSessionDescriptor *)sessionDescriptor
                                     andCallController:(CallController *)callController;

/// Result has type Future(HttpResponse)
+ (TOCFuture *)asyncSignalTooBusyToAnswerCallWithSessionDescriptor:(ResponderSessionDescriptor *)sessionDescriptor;

@end
