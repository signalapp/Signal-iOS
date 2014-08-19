#import "CallController.h"
#import "Util.h"
#import "Environment.h"
#import "SignalUtil.h"

@implementation CallController {
    UIBackgroundTaskIdentifier backgroundtask;
}

+(CallController*) callControllerForCallInitiatedLocally:(bool)initiatedLocally
                                        withRemoteNumber:(PhoneNumber*)remoteNumber
                           andOptionallySpecifiedContact:(Contact*)contact {
    require(remoteNumber != nil);

    CallController* instance = [CallController new];
    CallProgress* initialProgress = [CallProgress callProgressWithType:CallProgressType_Connecting];
    instance->progress = [ObservableValueController observableValueControllerWithInitialValue:initialProgress];
    instance->termination = [FutureSource new];
    instance->shortAuthenticationString = [FutureSource new];
    instance->canceller = [CancelTokenSource cancelTokenSource];
    instance->interactiveCallAcceptedOrDenied = [FutureSource new];
    instance->initiatedLocally = initiatedLocally;
    instance->remoteNumber = remoteNumber;
    instance->potentiallySpecifiedContact = contact;
    instance->exposedCallState = [CallState callStateWithObservableProgress:instance->progress
                                                       andFutureTermination:instance->termination
                                                               andFutureSas:instance->shortAuthenticationString
                                                            andRemoteNumber:instance->remoteNumber
                                                        andInitiatedLocally:instance->initiatedLocally
                                             andPotentiallySpecifiedContact:instance->potentiallySpecifiedContact
                                                          andFutureAccepted:instance->interactiveCallAcceptedOrDenied];
    
    return instance;
}

-(void) setCallAudioManager:(CallAudioManager*) _callAudioManager {
	callAudioManager = _callAudioManager;
}

-(bool) isInitiator {
    return initiatedLocally;
}

-(ErrorHandlerBlock) errorHandler {
    return ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) {
            if ([error isKindOfClass:[CallTermination class]]) {
                CallTermination* t = error;
                [self terminateWithReason:t.type
                          withFailureInfo:t.failure
                           andRelatedInfo:t.messageInfo];
            } else {
                [self terminateWithReason:CallTerminationType_UncategorizedFailure
                          withFailureInfo:error
                           andRelatedInfo:relatedInfo];
            }
        }
        
        [Environment errorNoter](error, relatedInfo, causedTermination);
    };
}
-(id<CancelToken>) untilCancelledToken {
    return [canceller getToken];
}
-(Future *)interactiveCallAccepted {
    return [interactiveCallAcceptedOrDenied then:^id(NSNumber* accepted) {
        if ([accepted boolValue]) return accepted;
        
        return [Future failed:[CallTermination callTerminationOfType:CallTerminationType_RejectedLocal
                                                         withFailure:accepted
                                                      andMessageInfo:nil]];
    }];
}
-(Future *)interactiveCallAcceptedOrDenied {
    return interactiveCallAcceptedOrDenied;
}
-(CallState*) callState {
    return exposedCallState;
}

-(void)unrestrictedAdvanceCallProgressTo:(enum CallProgressType)type {
    [progress adjustValue:^id(CallProgress* oldValue) {
        if (type < [oldValue type]) return oldValue;
        return [CallProgress callProgressWithType:type];
    }];
}

-(void)advanceCallProgressTo:(enum CallProgressType)type {
    require(type < CallProgressType_Talking);
    
    [self unrestrictedAdvanceCallProgressTo:type];
}
-(void)hangupOrDenyCall {
    bool didDeny = [interactiveCallAcceptedOrDenied trySetResult:@NO];
    
    enum CallTerminationType terminationType = didDeny
                                             ? CallTerminationType_RejectedLocal
                                             : CallTerminationType_HangupLocal;
    [self terminateWithReason:terminationType
              withFailureInfo:nil
               andRelatedInfo:nil];
}
-(void)acceptCall {
    [interactiveCallAcceptedOrDenied trySetResult:@YES];
}

-(void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString*)sas {
    require(sas != nil);
    [shortAuthenticationString trySetResult:sas];
    [self unrestrictedAdvanceCallProgressTo:CallProgressType_Talking];
}

-(void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo {
    enum CallProgressType progressType = ((CallProgress*)[progress currentValue]).type;
    bool hasAcceptedAlready = progressType > CallProgressType_Ringing;
    enum CallTerminationType terminationType = hasAcceptedAlready
                                             ? CallTerminationType_HangupRemote
                                             : CallTerminationType_RejectedRemote;
    
    [self terminateWithReason:terminationType
              withFailureInfo:failureInfo
               andRelatedInfo:relatedInfo];
}
-(void)terminateWithReason:(enum CallTerminationType)reason
           withFailureInfo:(id)failureInfo
            andRelatedInfo:(id)relatedInfo {
    
    CallTermination* t = [CallTermination callTerminationOfType:reason
                                                    withFailure:failureInfo
                                                 andMessageInfo:relatedInfo];
    
    if (![termination trySetResult:t]) return;
    [self unrestrictedAdvanceCallProgressTo:CallProgressType_Terminated];
    [interactiveCallAcceptedOrDenied trySetFailure:t];
    [canceller cancel];
    [shortAuthenticationString trySetFailure:t];
    [progress sealValue];
}

-(BOOL) toggleMute {
	return [callAudioManager toggleMute];
}

-(void) enableBackground {
    [progress watchLatestValueOnArbitraryThread:^(CallProgress* latestProgress) {
        if( CallProgressType_Connecting == latestProgress.type) {
            backgroundtask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
                //todo: handle premature expiration
            }];
        }else if(CallProgressType_Terminated == latestProgress.type){
            [UIApplication.sharedApplication endBackgroundTask:backgroundtask];
        }
    } untilCancelled:canceller.getToken];
}
@end
