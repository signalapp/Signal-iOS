#import <Foundation/Foundation.h>
#import "CallAudioManager.h"
#import "CallState.h"
#import "CallProgress.h"
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
@interface CallController : NSObject

@property (strong, nonatomic) CallAudioManager* callAudioManager;
@property (nonatomic, readonly, getter=isInitiator) bool initiatedLocally;

- (instancetype)initForCallInitiatedLocally:(bool)initiatedLocally
                           withRemoteNumber:(PhoneNumber*)remoteNumber
              andOptionallySpecifiedContact:(Contact*)contact;

- (void)advanceCallProgressTo:(CallProgressType)type;
- (void)hangupOrDenyCall;
- (void)acceptCall;
- (void)advanceCallProgressToConversingWithShortAuthenticationString:(NSString*)sas;
- (void)terminateWithReason:(CallTerminationType)reason
           withFailureInfo:(id)failureInfo
            andRelatedInfo:(id)relatedInfo;
- (void)terminateWithRejectionOrRemoteHangupAndFailureInfo:(id)failureInfo andRelatedInfo:(id)relatedInfo;
- (BOOL)toggleMute;
- (TOCFuture*)interactiveCallAccepted;
- (ErrorHandlerBlock)errorHandler;
- (TOCCancelToken*)untilCancelledToken;
- (CallState*)callState;

@end

