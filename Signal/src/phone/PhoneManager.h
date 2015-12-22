#import <Foundation/Foundation.h>
#import "CallAudioManager.h"
#import "CallConnectUtil.h"
#import "CallController.h"
#import "Contact.h"
#import "Environment.h"
#import "InitiatorSessionDescriptor.h"
#import "Logging.h"
#import "PhoneNumber.h"
#import "ResponderSessionDescriptor.h"
#import "Terminable.h"

/**
 *
 * PhoneManager is the highest level class, just below the UI layer.
 * It is in charge of the state of the phone (calling, busy, etc).
 * User actions like 'make a call' should roughly translate one-to-one with the exposed methods.
 *
 */
@interface PhoneManager : NSObject <Terminable> {
   @private
    ObservableValueController *currentCallControllerObservable;
   @private
    ObservableValueController *currentCallStateObservable;
   @private
    int64_t lastIncomingSessionId;
}

@property (readonly, nonatomic, copy) ErrorHandlerBlock errorHandler;

- (void)initiateOutgoingCallToRemoteNumber:(PhoneNumber *)remoteNumber;
- (void)initiateOutgoingCallToContact:(Contact *)contact atRemoteNumber:(PhoneNumber *)remoteNumber;
- (void)incomingCallWithSession:(ResponderSessionDescriptor *)session;
- (void)hangupOrDenyCall;
- (void)answerCall;
- (BOOL)toggleMute;
- (void)backgroundTimeExpired;

- (ObservableValue *)currentCallObservable;

+ (PhoneManager *)phoneManagerWithErrorHandler:(ErrorHandlerBlock)errorHandler;

@end
