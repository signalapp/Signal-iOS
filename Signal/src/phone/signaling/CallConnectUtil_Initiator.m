#import "CallConnectUtil_Initiator.h"

#import "CallConnectUtil.h"
#import "CallConnectUtil_Server.h"
#import "IgnoredPacketFailure.h"
#import "SignalUtil.h"
#import "UnrecognizedRequestFailure.h"
#import "Util.h"
#import "ZrtpManager.h"

@implementation CallConnectUtil_Initiator

+(Future*) asyncConnectCallToRemoteNumber:(PhoneNumber*)remoteNumber
                       withCallController:(CallController*)callController {
    
    require(remoteNumber != nil);
    require(callController != nil);
    require([callController isInitiator]);
    
    Future* futureInitiatorSessionDescriptor = [self asyncConnectToSignalServerAndGetInitiatorSessionDescriptorWithCallController:callController];
    
    return [futureInitiatorSessionDescriptor then:^(InitiatorSessionDescriptor* session) {
        return [CallConnectUtil_Server asyncConnectCallOverRelayDescribedInInitiatorSessionDescriptor:session
                                                                                   withCallController:callController
                                                                                    andInteropOptions:@[]];
    }];
}

+(Future*) asyncConnectToSignalServerAndGetInitiatorSessionDescriptorWithCallController:(CallController*)callController {
    require(callController != nil);
    
    Future* futureSignalConnection = [CallConnectUtil_Server asyncConnectToDefaultSignalingServerUntilCancelled:[callController untilCancelledToken]];
    
    return [futureSignalConnection then:^(HttpManager* httpManager) {
        requireState([httpManager isKindOfClass:[HttpManager class]]);
        
        FutureSource* predeclaredFutureSession = [FutureSource new];
        
        HttpResponse*(^serverRequestHandler)(HttpRequest*) = ^(HttpRequest* remoteRequest) {
            return [self respondToServerRequest:remoteRequest
                        usingEventualDescriptor:predeclaredFutureSession
                              andCallController:callController];
        };
        
        [httpManager startWithRequestHandler:serverRequestHandler
                             andErrorHandler:[callController errorHandler]
                              untilCancelled:[callController untilCancelledToken]];
        
        HttpRequest* initiateRequest = [HttpRequest httpRequestToInitiateToRemoteNumber:[callController callState].remoteNumber];
        Future* futureResponseToInitiate = [httpManager asyncOkResponseForRequest:initiateRequest
                                                                  unlessCancelled:[callController untilCancelledToken]];
        Future* futureResponseToInitiateWithInterpretedFailures = [futureResponseToInitiate catch:^(id error) {
            if ([error isKindOfClass:[HttpResponse class]]) {
                HttpResponse* badResponse = error;
                return [Future failed:[self callTerminationForBadResponse:badResponse
                                                        toInitiateRequest:initiateRequest]];
            }
            
            return [Future failed:error];
        }];
        
        Future* futureSession = [futureResponseToInitiateWithInterpretedFailures then:^(HttpResponse* response) {
            return [InitiatorSessionDescriptor initiatorSessionDescriptorFromJson:[response getOptionalBodyText]];
        }];
        [predeclaredFutureSession trySetResult:futureSession];
        
        return futureSession;
    }];
}

+(CallTermination*) callTerminationForBadResponse:(HttpResponse*)badResponse
                                toInitiateRequest:(HttpRequest*)initiateRequest {
    require(badResponse != nil);
    require(initiateRequest != nil);
    
    switch ([badResponse getStatusCode]) {
        case SIGNAL_STATUS_CODE_NO_SUCH_USER:
            return [CallTermination callTerminationOfType:CallTerminationType_NoSuchUser
                                              withFailure:badResponse
                                           andMessageInfo:initiateRequest];
        case SIGNAL_STATUS_CODE_SERVER_MESSAGE:
            return [CallTermination callTerminationOfType:CallTerminationType_ServerMessage
                                              withFailure:badResponse
                                           andMessageInfo:[badResponse getOptionalBodyText]];
        case SIGNAL_STATUS_CODE_LOGIN_FAILED:
            return [CallTermination callTerminationOfType:CallTerminationType_LoginFailed
                                              withFailure:badResponse
                                           andMessageInfo:initiateRequest];
        default:
            return [CallTermination callTerminationOfType:CallTerminationType_BadInteractionWithServer
                                              withFailure:badResponse
                                           andMessageInfo:initiateRequest];
    }
}

+(HttpResponse*) respondToServerRequest:(HttpRequest*)request
                usingEventualDescriptor:(Future*)futureInitiatorSessionDescriptor
                      andCallController:(CallController*)callController {
    require(request != nil);
    require(futureInitiatorSessionDescriptor != nil);
    require(callController != nil);
    
    // heart beat?
    if ([request isKeepAlive]) {
        return [HttpResponse httpResponse200Ok];
    }
    
    // too soon?
    if (![futureInitiatorSessionDescriptor hasSucceeded]) {
        [callController terminateWithReason:CallTerminationType_BadInteractionWithServer
                            withFailureInfo:[IgnoredPacketFailure new:@"Didn't receive session id from signaling server. Not able to understand request."]
                             andRelatedInfo:request];
        return [HttpResponse httpResponse500InternalServerError];
    }
    int64_t sessionId = [[futureInitiatorSessionDescriptor forceGetResult] sessionId];
    
    // hangup?
    if ([request isHangupForSession:sessionId]) {
        [callController terminateWithRejectionOrRemoteHangupAndFailureInfo:nil
                                                            andRelatedInfo:request];
        return [HttpResponse httpResponse200Ok];
    }
    
    // ringing?
    if ([request isRingingForSession:sessionId]) {
        [callController advanceCallProgressTo:CallProgressType_Ringing];
        return [HttpResponse httpResponse200Ok];
    }
    
    // busy signal?
    if ([request isBusyForSession:sessionId]) {
        [callController terminateWithReason:CallTerminationType_ResponderIsBusy
                            withFailureInfo:nil
                             andRelatedInfo:request];
        return [HttpResponse httpResponse200Ok];
    }
    
    // errr.....
    [callController terminateWithReason:CallTerminationType_BadInteractionWithServer
                        withFailureInfo:[UnrecognizedRequestFailure new:@"Didn't understand signaling server."]
                         andRelatedInfo:request];
    return [HttpResponse httpResponse501NotImplemented];
}

@end
