#import <Foundation/Foundation.h>
#import "CallAudioManager.h"
#import "CallProgress.h"
#import "CallState.h"
#import "CallTermination.h"
#import "PacketHandler.h"

/**
 *
 * CallController is where information about the progress and termination of a call is collected.
 * It is responsible for distilling call events from various components into something usable by the UI.
 *
 * Components can indicate the call is progressing by calling advance with a progress type.
 * Components can terminate the call by calling terminate with a reason.
 *
 * CallController takes care of ensuring progress never goes backwards, maintaining thread safety, etc.
 *
 */
@interface CallController : NSObject {
   @private
    ObservableValueController *progress;
   @private
    TOCFutureSource *termination;
   @private
    TOCFutureSource *shortAuthenticationString;
   @private
    TOCCancelTokenSource *canceller;
   @private
    TOCFutureSource *interactiveCallAcceptedOrDenied;
   @private
    bool initiatedLocally;
   @private
    PhoneNumber *remoteNumber;
   @private
    CallState *exposedCallState;
   @private
    Contact *potentiallySpecifiedContact;
   @private
    CallAudioManager *callAudioManager;
}

+ (CallController *)callControllerForCallInitiatedLocally:(bool)initiatedLocally
                                         withRemoteNumber:(PhoneNumber *)remoteNumber
                            andOptionallySpecifiedContact:(Contact *)contact;

- (void)setCallAudioManager:(CallAudioManager *)callAudioManager;
- (void)advanceCallProgressTo:(enum CallProgressType)type;
- (void)hangupOrDenyCall;
- (void)acceptCall;
- (void)backgroundTimeExpired;
- (void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString *)sas;
- (void)terminateWithReason:(enum CallTerminationType)reason
            withFailureInfo:(id)failureInfo
             andRelatedInfo:(id)relatedInfo;
- (void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo;
- (BOOL)toggleMute;
- (bool)isInitiator;
- (TOCFuture *)interactiveCallAccepted;
- (ErrorHandlerBlock)errorHandler;
- (TOCCancelToken *)untilCancelledToken;
- (CallState *)callState;

@end
