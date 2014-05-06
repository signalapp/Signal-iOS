#import <Foundation/Foundation.h>
#import "CallAudioManager.h"
#import "CallState.h"
#import "CallProgress.h"
#import "CallTermination.h"
#import "CancelTokenSource.h"
#import "FutureSource.h"
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
@private ObservableValueController* progress;
@private FutureSource* termination;
@private FutureSource* shortAuthenticationString;
@private CancelTokenSource* canceller;
@private FutureSource* interactiveCallAcceptedOrDenied;
@private bool initiatedLocally;
@private PhoneNumber* remoteNumber;
@private CallState* exposedCallState;
@private Contact* potentiallySpecifiedContact;
@private CallAudioManager *callAudioManager;
}

+(CallController*) callControllerForCallInitiatedLocally:(bool)initiatedLocally
                                        withRemoteNumber:(PhoneNumber*)remoteNumber
                           andOptionallySpecifiedContact:(Contact*)contact;

-(void)setCallAudioManager:(CallAudioManager*) callAudioManager;
-(void)advanceCallProgressTo:(enum CallProgressType)type;
-(void)hangupOrDenyCall;
-(void)acceptCall;
-(void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString*)sas;
-(void)terminateWithReason:(enum CallTerminationType)reason
           withFailureInfo:(id)failureInfo
            andRelatedInfo:(id)relatedInfo;
-(void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo;
-(BOOL)toggleMute;
-(bool) isInitiator;
-(Future*)interactiveCallAccepted;
-(ErrorHandlerBlock)errorHandler;
-(id<CancelToken>)untilCancelledToken;
-(CallState*)callState;

@end

