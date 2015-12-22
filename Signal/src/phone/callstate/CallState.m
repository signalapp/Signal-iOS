#import "CallState.h"
#import "Util.h"

@implementation CallState

@synthesize observableProgress;
@synthesize futureTermination;
@synthesize remoteNumber;
@synthesize futureShortAuthenticationString;
@synthesize initiatedLocally;
@synthesize potentiallySpecifiedContact;
@synthesize futureCallLocallyAcceptedOrRejected;

+ (CallState *)callStateWithObservableProgress:(ObservableValue *)observableProgress
                          andFutureTermination:(TOCFuture *)futureTermination
                                  andFutureSas:(TOCFuture *)futureSas
                               andRemoteNumber:(PhoneNumber *)remoteNumber
                           andInitiatedLocally:(bool)initiatedLocally
                andPotentiallySpecifiedContact:(Contact *)contact
                             andFutureAccepted:(TOCFuture *)futureCallLocallyAcceptedOrRejected {
    ows_require(observableProgress != nil);
    ows_require(futureTermination != nil);
    ows_require(futureSas != nil);
    ows_require(remoteNumber != nil);
    ows_require(futureCallLocallyAcceptedOrRejected != nil);

    CallState *call                           = [CallState new];
    call->observableProgress                  = observableProgress;
    call->futureTermination                   = futureTermination;
    call->futureShortAuthenticationString     = futureSas;
    call->remoteNumber                        = remoteNumber;
    call->initiatedLocally                    = initiatedLocally;
    call->potentiallySpecifiedContact         = contact;
    call->futureCallLocallyAcceptedOrRejected = futureCallLocallyAcceptedOrRejected;
    return call;
}

@end
