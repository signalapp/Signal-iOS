#import "CallController.h"
#import "Util.h"
#import "Environment.h"
#import "HttpRequest+SignalUtil.h"

@interface CallController ()

@property (strong, nonatomic) ObservableValueController*  progress;
@property (strong, nonatomic) TOCCancelTokenSource*       canceller;
@property (strong, nonatomic) TOCFutureSource*            termination;
@property (strong, nonatomic) TOCFutureSource*            shortAuthenticationString;
@property (strong, nonatomic) TOCFutureSource*            interactiveCallAcceptedOrDenied;
@property (strong, nonatomic) CallState*                  exposedCallState;
@property (strong, nonatomic) PhoneNumber*                remoteNumber;
@property (strong, nonatomic) Contact*                    potentiallySpecifiedContact;
@property (nonatomic)         UIBackgroundTaskIdentifier  backgroundtask;
@property (nonatomic, readwrite, getter=isInitiator) bool initiatedLocally;

@end

@implementation CallController

- (instancetype)initForCallInitiatedLocally:(bool)initiatedLocally
                           withRemoteNumber:(PhoneNumber*)remoteNumber
              andOptionallySpecifiedContact:(Contact*)contact {
    if (self = [super init]) {
        require(remoteNumber != nil);
        
        CallProgress* initialProgress =        [[CallProgress alloc] initWithType:CallProgressTypeConnecting];
        self.progress =                        [[ObservableValueController alloc] initWithInitialValue:initialProgress];
        self.canceller =                       [[TOCCancelTokenSource alloc] init];
        self.termination =                     [[TOCFutureSource alloc] init];
        self.shortAuthenticationString =       [[TOCFutureSource alloc] init];
        self.interactiveCallAcceptedOrDenied = [[TOCFutureSource alloc] init];
        self.initiatedLocally =                initiatedLocally;
        self.remoteNumber =                    remoteNumber;
        self.potentiallySpecifiedContact =     contact;
        
        self.exposedCallState = [[CallState alloc] initWithObservableProgress:self.progress
                                                         andFutureTermination:self.termination.future
                                                                 andFutureSas:self.shortAuthenticationString.future
                                                              andRemoteNumber:self.remoteNumber
                                                          andInitiatedLocally:self.initiatedLocally
                                               andPotentiallySpecifiedContact:self.potentiallySpecifiedContact
                                                            andFutureAccepted:self.interactiveCallAcceptedOrDenied.future];
    }
    
    return self;
}

- (ErrorHandlerBlock)errorHandler {
    return ^(id error, id relatedInfo, bool causedTermination) {
        if (causedTermination) {
            if ([error isKindOfClass:CallTermination.class]) {
                CallTermination* t = error;
                [self terminateWithReason:t.type
                          withFailureInfo:t.failure
                           andRelatedInfo:t.messageInfo];
            } else {
                [self terminateWithReason:CallTerminationTypeUncategorizedFailure
                          withFailureInfo:error
                           andRelatedInfo:relatedInfo];
            }
        }
        
        Environment.errorNoter(error, relatedInfo, causedTermination);
    };
}

- (TOCCancelToken*)untilCancelledToken {
    return self.canceller.token;
}

- (TOCFuture*)interactiveCallAccepted {
    return [self.interactiveCallAcceptedOrDenied.future thenTry:^id(NSNumber* accepted) {
        if ([accepted boolValue]) return accepted;
        
        return [TOCFuture futureWithFailure:[[CallTermination alloc] initWithType:CallTerminationTypeRejectedLocal
                                                                       andFailure:accepted
                                                                   andMessageInfo:nil]];
    }];
}

- (CallState*)callState {
    return self.exposedCallState;
}

- (void)unrestrictedAdvanceCallProgressTo:(CallProgressType)type {
    [self.progress adjustValue:^id(CallProgress* oldValue) {
        if (type < [oldValue type]) return oldValue;
        return [[CallProgress alloc] initWithType:type];
    }];
}

- (void)advanceCallProgressTo:(CallProgressType)type {
    require(type < CallProgressTypeTalking);
    
    [self unrestrictedAdvanceCallProgressTo:type];
}

- (void)hangupOrDenyCall {
    bool didDeny = [self.interactiveCallAcceptedOrDenied trySetResult:@NO];
    
    CallTerminationType terminationType = didDeny
                                             ? CallTerminationTypeRejectedLocal
                                             : CallTerminationTypeHangupLocal;
    [self terminateWithReason:terminationType
              withFailureInfo:nil
               andRelatedInfo:nil];
}

- (void)acceptCall {
    [self.interactiveCallAcceptedOrDenied trySetResult:@YES];
}

- (void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString*)sas {
    require(sas != nil);
    [self.shortAuthenticationString trySetResult:sas];
    [self unrestrictedAdvanceCallProgressTo:CallProgressTypeTalking];
}

- (void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo {
    CallProgressType progressType = ((CallProgress*)self.progress.currentValue).type;
    bool hasAcceptedAlready = progressType > CallProgressTypeRinging;
    CallTerminationType terminationType = hasAcceptedAlready
                                             ? CallTerminationTypeHangupRemote
                                             : CallTerminationTypeRejectedRemote;
    
    [self terminateWithReason:terminationType
              withFailureInfo:failureInfo
               andRelatedInfo:relatedInfo];
}

- (void)terminateWithReason:(CallTerminationType)reason
            withFailureInfo:(id)failureInfo
             andRelatedInfo:(id)relatedInfo {
    
    CallTermination* t = [[CallTermination alloc] initWithType:reason
                                                    andFailure:failureInfo
                                                andMessageInfo:relatedInfo];
    
    if (![self.termination trySetResult:t]) return;
    [self unrestrictedAdvanceCallProgressTo:CallProgressTypeTerminated];
    [self.interactiveCallAcceptedOrDenied trySetFailure:t];
    [self.canceller cancel];
    [self.shortAuthenticationString trySetFailure:t];
    [self.progress sealValue];
}

- (BOOL)toggleMute {
	return [self.callAudioManager toggleMute];
}

- (void)enableBackground {
    [self.progress watchLatestValueOnArbitraryThread:^(CallProgress* latestProgress) {
        if (CallProgressTypeConnecting == latestProgress.type) {
            self.backgroundtask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
                //todo: handle premature expiration
            }];
        } else if (CallProgressTypeTerminated == latestProgress.type) {
            [UIApplication.sharedApplication endBackgroundTask:self.backgroundtask];
        }
    } untilCancelled:self.canceller.token];
}
@end
