#import "CallAudioManager.h"
#import "PhoneManager.h"
#import "ThreadManager.h"
#import "CallTermination.h"
#import "CallFailedServerMessage.h"
#import "CallProgress.h"
#import "RecentCallManager.h"
#import "Util.h"

@implementation PhoneManager

+(PhoneManager*) phoneManagerWithErrorHandler:(ErrorHandlerBlock)errorHandler {
    PhoneManager* m = [PhoneManager new];
    m->_errorHandler = errorHandler;
    m->currentCallControllerObservable = [ObservableValueController observableValueControllerWithInitialValue:nil];
    m->currentCallStateObservable = [ObservableValueController observableValueControllerWithInitialValue:nil];

    [m->currentCallControllerObservable watchLatestValue:^(CallController* latestValue) {
        [m->currentCallStateObservable updateValue:[latestValue callState]];
    } onThread:[NSThread currentThread] untilCancelled:nil];
    
    return m;
}

-(ObservableValue*) currentCallObservable {
    return currentCallStateObservable;
}

-(CallController*) cancelExistingCallAndInitNewCallWork:(bool)initiatedLocally
                                                 remote:(PhoneNumber*)remoteNumber
                                        optionalContact:(Contact*)contact {
    CallController* old = [self curCallController];
    CallController* new = [CallController callControllerForCallInitiatedLocally:initiatedLocally
                                                               withRemoteNumber:remoteNumber
                                                  andOptionallySpecifiedContact:contact];
    [old terminateWithReason:CallTerminationType_ReplacedByNext
             withFailureInfo:nil
              andRelatedInfo:nil];
    [currentCallControllerObservable updateValue:new];
    return new;
}

-(void) initiateOutgoingCallToContact:(Contact*)contact atRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:contact];
}

-(void) initiateOutgoingCallToRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:nil];
}

-(void) initiateOutgoingCallToRemoteNumber:(PhoneNumber*)remoteNumber withOptionallyKnownContact:(Contact*)contact {
    require(remoteNumber != nil);
	
    CallController* callController = [self cancelExistingCallAndInitNewCallWork:true
                                                                         remote:remoteNumber
                                                                optionalContact:contact];
    [callController acceptCall]; // initiator implicitly accepts call
    id<CancelToken> lifetime = [callController untilCancelledToken];
        
    Future* futureConnected = [CallConnectUtil asyncInitiateCallToRemoteNumber:remoteNumber
                                                         andCallController:callController];
    
    Future* futureCalling = [futureConnected then:^id(CallConnectResult* connectResult) {
        [callController advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
        CallAudioManager *cam = [CallAudioManager callAudioManagerStartedWithAudioSocket:connectResult.audioSocket
                                                 andErrorHandler:[callController errorHandler]
                                                  untilCancelled:lifetime];
		[callController setCallAudioManager:cam];
        return nil;
    }];
    
    [futureCalling catchDo:^(id error) {
        [callController errorHandler](error, nil, true);
    }];
}

-(void) incomingCallWithSession:(ResponderSessionDescriptor*)session {
    require(session != nil);

    int64_t prevSession = lastIncomingSessionId;
    lastIncomingSessionId = session.sessionId;

    if ([[[[currentCallControllerObservable currentValue] callState] futureTermination] isIncomplete]) {
        if (session.sessionId == prevSession) {
            [Environment errorNoter](@"Ignoring duplicate incoming call signal.", session, false);
            return;
        }

        [[[Environment getCurrent] recentCallManager] addMissedCallDueToBusy:session];
        
        [[CallConnectUtil asyncSignalTooBusyToAnswerCallWithSessionDescriptor:session] catchDo:^(id error) {
            [Environment errorNoter](error, @"Failed to signal busy.", false);
        }];
        return;
    }
    
    Contact* callingContact = [[[Environment getCurrent] contactsManager] latestContactForPhoneNumber:session.initiatorNumber];
    CallController* callController = [self cancelExistingCallAndInitNewCallWork:false
                                                                         remote:session.initiatorNumber
                                                                optionalContact:callingContact];

    id<CancelToken> lifetime = [callController untilCancelledToken];
    
    Future* futureConnected = [CallConnectUtil asyncRespondToCallWithSessionDescriptor:session
                                                                     andCallController:callController];
    
    Future* futureStarted = [futureConnected then:^id(CallConnectResult* connectResult) {
        [callController advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
        CallAudioManager* cam = [CallAudioManager callAudioManagerStartedWithAudioSocket:connectResult.audioSocket
                                                 andErrorHandler:[callController errorHandler]
                                                  untilCancelled:lifetime];
		[callController setCallAudioManager:cam];
        return nil;
    }];
    
    [futureStarted catchDo:^(id error) {
        [callController errorHandler](error, nil, true);
    }];
}
-(CallController*) curCallController {
    return [currentCallControllerObservable currentValue];
}
-(void) answerCall {
    [[self curCallController] acceptCall];
}
-(void) hangupOrDenyCall {
    [[self curCallController] hangupOrDenyCall];
}

-(BOOL) toggleMute{
	return [self.curCallController toggleMute];
}

-(void)terminate{
    [[self curCallController] terminateWithReason:CallTerminationType_UncategorizedFailure
                                  withFailureInfo:@"PhoneManager terminated"
                                   andRelatedInfo:nil];
}

@end
