#import "AppAudioManager.h"
#import "CallAudioManager.h"
#import "PhoneManager.h"
#import "RecentCallManager.h"

@implementation PhoneManager

+ (PhoneManager *)phoneManagerWithErrorHandler:(ErrorHandlerBlock)errorHandler {
    PhoneManager *m                    = [PhoneManager new];
    m->_errorHandler                   = errorHandler;
    m->currentCallControllerObservable = [ObservableValueController observableValueControllerWithInitialValue:nil];
    m->currentCallStateObservable      = [ObservableValueController observableValueControllerWithInitialValue:nil];

    [m->currentCallControllerObservable watchLatestValue:^(CallController *latestValue) {
      [m->currentCallStateObservable updateValue:latestValue.callState];
    }
                                                onThread:NSThread.currentThread
                                          untilCancelled:nil];

    return m;
}

- (ObservableValue *)currentCallObservable {
    return currentCallStateObservable;
}

- (CallController *)cancelExistingCallAndInitNewCallWork:(bool)initiatedLocally
                                                  remote:(PhoneNumber *)remoteNumber
                                         optionalContact:(Contact *)contact {
    CallController *old = [self curCallController];
    CallController *new = [
        CallController callControllerForCallInitiatedLocally : initiatedLocally withRemoteNumber : remoteNumber
            andOptionallySpecifiedContact : contact
    ];
    [old terminateWithReason:CallTerminationType_ReplacedByNext withFailureInfo:nil andRelatedInfo:nil];
    [currentCallControllerObservable updateValue:new];
    return new;
}

- (void)initiateOutgoingCallToContact:(Contact *)contact atRemoteNumber:(PhoneNumber *)remoteNumber {
    ows_require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:contact];
}

- (void)initiateOutgoingCallToRemoteNumber:(PhoneNumber *)remoteNumber {
    ows_require(remoteNumber != nil);
    [self initiateOutgoingCallToRemoteNumber:remoteNumber withOptionallyKnownContact:nil];
}

- (void)initiateOutgoingCallToRemoteNumber:(PhoneNumber *)remoteNumber withOptionallyKnownContact:(Contact *)contact {
    ows_require(remoteNumber != nil);

    [[AppAudioManager sharedInstance] requestRequiredPermissionsIfNeededWithCompletion:^(BOOL granted) {
      if (granted) {
          [self callToRemoteNumber:remoteNumber withOptionallyKnownContact:contact];
      }
    }
                                                                              incoming:NO];
}

- (void)callToRemoteNumber:(PhoneNumber *)remoteNumber withOptionallyKnownContact:(Contact *)contact {
    CallController *callController =
        [self cancelExistingCallAndInitNewCallWork:true remote:remoteNumber optionalContact:contact];
    [callController acceptCall]; // initiator implicitly accepts call
    TOCCancelToken *lifetime = [callController untilCancelledToken];

    TOCFuture *futureConnected =
        [CallConnectUtil asyncInitiateCallToRemoteNumber:remoteNumber andCallController:callController];

    TOCFuture *futureCalling = [futureConnected thenTry:^id(CallConnectResult *connectResult) {
      [callController
          advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
      CallAudioManager *cam = [CallAudioManager callAudioManagerStartedWithAudioSocket:connectResult.audioSocket
                                                                       andErrorHandler:callController.errorHandler
                                                                        untilCancelled:lifetime];
      [callController setCallAudioManager:cam];
      return nil;
    }];

    [futureCalling catchDo:^(id error) {
      callController.errorHandler(error, nil, true);
    }];
}

- (void)incomingCallWithSession:(ResponderSessionDescriptor *)session {
    ows_require(session != nil);

    int64_t prevSession   = lastIncomingSessionId;
    lastIncomingSessionId = session.sessionId;

    if ([currentCallControllerObservable.currentValue callState].futureTermination.isIncomplete) {
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

    [[AppAudioManager sharedInstance] requestRequiredPermissionsIfNeededWithCompletion:^(BOOL granted) {
      if (granted) {
          Contact *callingContact =
              [Environment.getCurrent.contactsManager latestContactForPhoneNumber:session.initiatorNumber];
          CallController *callController = [self cancelExistingCallAndInitNewCallWork:false
                                                                               remote:session.initiatorNumber
                                                                      optionalContact:callingContact];

          TOCCancelToken *lifetime = [callController untilCancelledToken];

          TOCFuture *futureConnected =
              [CallConnectUtil asyncRespondToCallWithSessionDescriptor:session andCallController:callController];

          TOCFuture *futureStarted = [futureConnected thenTry:^id(CallConnectResult *connectResult) {
            [callController
                advanceCallProgressToConversingWithShortAuthenticationString:connectResult.shortAuthenticationString];
            CallAudioManager *cam = [CallAudioManager callAudioManagerStartedWithAudioSocket:connectResult.audioSocket
                                                                             andErrorHandler:callController.errorHandler
                                                                              untilCancelled:lifetime];
            [callController setCallAudioManager:cam];
            return nil;
          }];

          [futureStarted catchDo:^(id error) {
            callController.errorHandler(error, nil, true);
          }];
      }
    }
                                                                              incoming:YES];
}
- (CallController *)curCallController {
    return currentCallControllerObservable.currentValue;
}

- (void)answerCall {
    [[self curCallController] acceptCall];
}

- (void)hangupOrDenyCall {
    [[self curCallController] hangupOrDenyCall];
}

- (void)backgroundTimeExpired {
    [[self curCallController] backgroundTimeExpired];
}

- (BOOL)toggleMute {
    return [self.curCallController toggleMute];
}

- (void)terminate {
    [[self curCallController] terminateWithReason:CallTerminationType_UncategorizedFailure
                                  withFailureInfo:@"PhoneManager terminated"
                                   andRelatedInfo:nil];
}

@end
