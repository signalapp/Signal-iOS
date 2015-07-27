#import "CallConnectUtil.h"
#import "CallConnectUtil_Initiator.h"
#import "CallConnectUtil_Responder.h"

@implementation CallConnectUtil

+(TOCFuture*) asyncInitiateCallToRemoteNumber:(PhoneNumber *)remoteNumber
                            andCallController:(CallController*)callController {
    require(remoteNumber != nil);
    require(callController != nil);
    return [CallConnectUtil_Initiator asyncConnectCallToRemoteNumber:remoteNumber
                                                  withCallController:callController];
}

+(TOCFuture*) asyncRespondToCallWithSessionDescriptor:(ResponderSessionDescriptor*)sessionDescriptor
                                    andCallController:(CallController*)callController {
    require(sessionDescriptor != nil);
    require(callController != nil);
    return [CallConnectUtil_Responder asyncConnectToIncomingCallWithSessionDescriptor:sessionDescriptor
                                                                  andCallController:callController];
}

+(TOCFuture*) asyncSignalTooBusyToAnswerCallWithSessionDescriptor:(ResponderSessionDescriptor*)sessionDescriptor {
    require(sessionDescriptor != nil);
    return [CallConnectUtil_Responder asyncSignalTooBusyToAnswerCallWithSessionDescriptor:sessionDescriptor];
}

@end
