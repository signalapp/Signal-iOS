#import <Foundation/Foundation.h>
#import "Contact.h"
#import "ObservableValue.h"
#import "PhoneNumber.h"

/**
 *
 * CallState exposes the state of a single call, in a simplified way intended to be consumed by the user interface code.
 *
 * The observable value observableProgress exposes values of type CallProgression that indicate the progression of the
 * call, from connecting through teminated.
 * The future futureTermination will eventually contain a CallTermination that indicates how the call terminated.
 * The future futureShortAuthenticationString will eventually contain the sas to display, or else a failure if the call
 * fails beforehand.
 * The remoteNumber field is what it sounds like.
 * The initiatedLocally field determines if we are the initiator of the call or the responder to a call.
 *
 * The futures exposed by this type are guaranteed to run callbacks (from then/catch/finally/etc) either inline or on
 * the main thread.
 *
 */
@interface CallState : NSObject

@property (nonatomic, readonly) ObservableValue *observableProgress;
@property (nonatomic, readonly) TOCFuture *futureTermination;
@property (nonatomic, readonly) TOCFuture *futureShortAuthenticationString;
@property (nonatomic, readonly) PhoneNumber *remoteNumber;
@property (nonatomic, readonly) bool initiatedLocally;
@property (nonatomic, readonly) Contact *potentiallySpecifiedContact;
@property (nonatomic, readonly) TOCFuture *futureCallLocallyAcceptedOrRejected;

+ (CallState *)callStateWithObservableProgress:(ObservableValue *)observableProgress
                          andFutureTermination:(TOCFuture *)futureTermination
                                  andFutureSas:(TOCFuture *)futureSas
                               andRemoteNumber:(PhoneNumber *)remoteNumber
                           andInitiatedLocally:(bool)initiatedLocally
                andPotentiallySpecifiedContact:(Contact *)contact
                             andFutureAccepted:(TOCFuture *)futureCallLocallyAcceptedOrRejected;

@end
