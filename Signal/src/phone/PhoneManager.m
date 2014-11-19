#import "CallAudioManager.h"
#import "PhoneManager.h"
#import "ThreadManager.h"
#import "CallTermination.h"
#import "CallFailedServerMessage.h"
#import "CallProgress.h"
#import "RecentCallManager.h"
#import "Util.h"

@interface PhoneManager ()

@property (strong, nonatomic) ObservableValueController* currentCallControllerObservable;
@property (strong, nonatomic) ObservableValueController* currentCallStateObservable;
@property (nonatomic) int64_t lastIncomingSessionId;
@property (nonatomic) ErrorHandlerBlock errorHandler;

@end

@implementation PhoneManager

- (instancetype)initWithErrorHandler:(ErrorHandlerBlock)errorHandler {
    if (self = [super init]) {
        self.errorHandler = errorHandler;
        self.currentCallControllerObservable = [[ObservableValueController alloc] initWithInitialValue:nil];
        self.currentCallStateObservable = [[ObservableValueController alloc] initWithInitialValue:nil];
        
        [self.currentCallControllerObservable watchLatestValue:^(CallController* latestValue) {
            [self.currentCallStateObservable updateValue:latestValue.callState];
        } onThread:[NSThread currentThread] untilCancelled:nil];
    }
    
    return self;
}

- (ObservableValue*)currentCallObservable {
    return self.currentCallStateObservable;
}

- (CallController*)cancelExistingCallAndInitNewCallWork:(bool)initiatedLocally
                                                 remote:(PhoneNumber*)remoteNumber
                                        optionalContact:(Contact*)contact {
    CallController* oldCallController = [self currentCallController];
    CallController* newCallController = [[CallController alloc] initForCallInitiatedLocally:initiatedLocally
                                                                           withRemoteNumber:remoteNumber
                                                              andOptionallySpecifiedContact:contact];
    [oldCallController terminateWithReason:CallTerminationTypeReplacedByNext
                           withFailureInfo:nil
                            andRelatedInfo:nil];
    [self.currentCallControllerObservable updateValue:newCallController];
    return newCallController;
}

- (void)initiateOutgoingCallToContact:(Contact*)contact atRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:contact];
}

- (void)initiateOutgoingCallToRemoteNumber:(PhoneNumber*)remoteNumber {
    require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:nil];
}

- (void)initiateOutgoingCallToRemoteNumber:(PhoneNumber*)remoteNumber withOptionallyKnownContact:(Contact*)contact {
    require(remoteNumber != nil);
	
    CallController* callController = [self cancelExistingCallAndInitNewCallWork:true
                                                                         remote:remoteNumber
                                                                optionalContact:contact];
    [callController acceptCall]; // initiator implicitly accepts call
    TOCCancelToken* lifetime = [callController untilCancelledToken];
        
    TOCFuture* futureConnected = [CallConnectUtil asyncInitiateCallToRemoteNumber:remoteNumber
                                                                andCallController:callController];
    
    TOCFuture* futureCalling = [futureConnected thenTry:^id(CallConnectResult* connectResult) {
        [callController advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
        CallAudioManager *cam = [[CallAudioManager alloc] initWithAudioSocket:connectResult.audioSocket
                                                              andErrorHandler:callController.errorHandler
                                                               untilCancelled:lifetime];
		[callController setCallAudioManager:cam];
        return nil;
    }];
    
    [futureCalling catchDo:^(id error) {
        callController.errorHandler(error, nil, true);
    }];
}

- (void)incomingCallWithSession:(ResponderSessionDescriptor*)session {
    require(session != nil);

    int64_t prevSession = self.lastIncomingSessionId;
    self.lastIncomingSessionId = session.sessionId;

    if ([[self currentCallController] callState].futureTermination.isIncomplete) {
        if (session.sessionId == prevSession) {
            Environment.errorNoter(@"Ignoring duplicate incoming call signal.", session, false);
            return;
        }

        [Environment.getCurrent.recentCallManager addMissedCallDueToBusy:session];
        
        [[CallConnectUtil asyncSignalTooBusyToAnswerCallWithSessionDescriptor:session] catchDo:^(id error) {
            Environment.errorNoter(error, @"Failed to signal busy.", false);
        }];
        return;
    }
    
    Contact* callingContact = [Environment.getCurrent.contactsManager latestContactForPhoneNumber:session.initiatorNumber];
    CallController* callController = [self cancelExistingCallAndInitNewCallWork:false
                                                                         remote:session.initiatorNumber
                                                                optionalContact:callingContact];

    TOCCancelToken* lifetime = [callController untilCancelledToken];
    
    TOCFuture* futureConnected = [CallConnectUtil asyncRespondToCallWithSessionDescriptor:session
                                                                        andCallController:callController];
    
    TOCFuture* futureStarted = [futureConnected thenTry:^id(CallConnectResult* connectResult) {
        [callController advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
        CallAudioManager* cam = [[CallAudioManager alloc] initWithAudioSocket:connectResult.audioSocket
                                                              andErrorHandler:callController.errorHandler
                                                               untilCancelled:lifetime];
		[callController setCallAudioManager:cam];
        return nil;
    }];
    
    [futureStarted catchDo:^(id error) {
        callController.errorHandler(error, nil, true);
    }];
}

- (CallController*)currentCallController {
    return self.currentCallControllerObservable.currentValue;
}

- (void)answerCall {
    [[self currentCallController] acceptCall];
}

- (void)hangupOrDenyCall {
    [[self currentCallController] hangupOrDenyCall];
}

- (BOOL)toggleMute {
	return [self.currentCallController toggleMute];
}

- (void)terminate {
    [[self currentCallController] terminateWithReason:CallTerminationTypeUncategorizedFailure
                                      withFailureInfo:@"PhoneManager terminated"
                                       andRelatedInfo:nil];
}

@end
