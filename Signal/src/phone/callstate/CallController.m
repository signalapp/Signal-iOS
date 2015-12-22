#import "CallController.h"

@implementation CallController {
    UIBackgroundTaskIdentifier backgroundtask;
}

+ (CallController *)callControllerForCallInitiatedLocally:(bool)initiatedLocally
                                         withRemoteNumber:(PhoneNumber *)remoteNumber
                            andOptionallySpecifiedContact:(Contact *)contact {
    ows_require(remoteNumber != nil);

    CallController *instance      = [CallController new];
    CallProgress *initialProgress = [CallProgress callProgressWithType:CallProgressType_Connecting];
    instance->progress    = [ObservableValueController observableValueControllerWithInitialValue:initialProgress];
    instance->termination = [TOCFutureSource new];
    instance->shortAuthenticationString       = [TOCFutureSource new];
    instance->canceller                       = [TOCCancelTokenSource new];
    instance->interactiveCallAcceptedOrDenied = [TOCFutureSource new];
    instance->initiatedLocally                = initiatedLocally;
    instance->remoteNumber                    = remoteNumber;
    instance->potentiallySpecifiedContact     = contact;
    instance->exposedCallState =
        [CallState callStateWithObservableProgress:instance->progress
                              andFutureTermination:instance->termination.future
                                      andFutureSas:instance->shortAuthenticationString.future
                                   andRemoteNumber:instance->remoteNumber
                               andInitiatedLocally:instance->initiatedLocally
                    andPotentiallySpecifiedContact:instance->potentiallySpecifiedContact
                                 andFutureAccepted:instance->interactiveCallAcceptedOrDenied.future];

    return instance;
}

- (void)setCallAudioManager:(CallAudioManager *)_callAudioManager {
    callAudioManager = _callAudioManager;
}

- (bool)isInitiator {
    return initiatedLocally;
}

- (ErrorHandlerBlock)errorHandler {
    return ^(id error, id relatedInfo, bool causedTermination) {
      if (causedTermination) {
          if ([error isKindOfClass:CallTermination.class]) {
              CallTermination *t = error;
              [self terminateWithReason:t.type withFailureInfo:t.failure andRelatedInfo:t.messageInfo];
          } else {
              [self terminateWithReason:CallTerminationType_UncategorizedFailure
                        withFailureInfo:error
                         andRelatedInfo:relatedInfo];
          }
      }

      Environment.errorNoter(error, relatedInfo, causedTermination);
    };
}
- (TOCCancelToken *)untilCancelledToken {
    return canceller.token;
}
- (TOCFuture *)interactiveCallAccepted {
    return [interactiveCallAcceptedOrDenied.future thenTry:^id(NSNumber *accepted) {
      if ([accepted boolValue])
          return accepted;

      return [TOCFuture futureWithFailure:[CallTermination callTerminationOfType:CallTerminationType_RejectedLocal
                                                                     withFailure:accepted
                                                                  andMessageInfo:nil]];
    }];
}
- (TOCFuture *)interactiveCallAcceptedOrDenied {
    return interactiveCallAcceptedOrDenied.future;
}
- (CallState *)callState {
    return exposedCallState;
}

- (void)unrestrictedAdvanceCallProgressTo:(enum CallProgressType)type {
    [progress adjustValue:^id(CallProgress *oldValue) {
      if (type < [oldValue type])
          return oldValue;
      return [CallProgress callProgressWithType:type];
    }];
}

- (void)advanceCallProgressTo:(enum CallProgressType)type {
    ows_require(type < CallProgressType_Talking);

    [self unrestrictedAdvanceCallProgressTo:type];
}

- (void)backgroundTimeExpired {
    [self terminateWithReason:CallTerminationType_BackgroundTimeExpired withFailureInfo:nil andRelatedInfo:nil];
}

- (void)hangupOrDenyCall {
    bool didDeny = [interactiveCallAcceptedOrDenied trySetResult:@NO];

    enum CallTerminationType terminationType =
        didDeny ? CallTerminationType_RejectedLocal : CallTerminationType_HangupLocal;
    [self terminateWithReason:terminationType withFailureInfo:nil andRelatedInfo:nil];
}
- (void)acceptCall {
    [interactiveCallAcceptedOrDenied trySetResult:@YES];
}

- (void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString *)sas {
    ows_require(sas != nil);
    [shortAuthenticationString trySetResult:sas];
    [self unrestrictedAdvanceCallProgressTo:CallProgressType_Talking];
}

- (void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo {
    enum CallProgressType progressType = ((CallProgress *)progress.currentValue).type;
    bool hasAcceptedAlready            = progressType > CallProgressType_Ringing;
    enum CallTerminationType terminationType =
        hasAcceptedAlready ? CallTerminationType_HangupRemote : CallTerminationType_RejectedRemote;

    [self terminateWithReason:terminationType withFailureInfo:failureInfo andRelatedInfo:relatedInfo];
}
- (void)terminateWithReason:(enum CallTerminationType)reason
            withFailureInfo:(id)failureInfo
             andRelatedInfo:(id)relatedInfo {
    CallTermination *t =
        [CallTermination callTerminationOfType:reason withFailure:failureInfo andMessageInfo:relatedInfo];

    if (![termination trySetResult:t])
        return;
    [self unrestrictedAdvanceCallProgressTo:CallProgressType_Terminated];
    [interactiveCallAcceptedOrDenied trySetFailure:t];
    [canceller cancel];
    [shortAuthenticationString trySetFailure:t];
    [progress sealValue];
}

- (BOOL)toggleMute {
    return [callAudioManager toggleMute];
}

- (void)enableBackground {
    [progress watchLatestValueOnArbitraryThread:^(CallProgress *latestProgress) {
      if (CallProgressType_Connecting == latestProgress.type) {
          backgroundtask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
              // todo: handle premature expiration
          }];
      } else if (CallProgressType_Terminated == latestProgress.type) {
          [UIApplication.sharedApplication endBackgroundTask:backgroundtask];
      }
    }
                                 untilCancelled:canceller.token];
}
@end
