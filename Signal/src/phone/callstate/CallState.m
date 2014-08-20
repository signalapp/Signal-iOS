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

+(CallState*) callStateWithObservableProgress:(ObservableValue*)observableProgress
                         andFutureTermination:(TOCFuture*)futureTermination
                                 andFutureSas:(TOCFuture*)futureSas
                              andRemoteNumber:(PhoneNumber*)remoteNumber
                          andInitiatedLocally:(bool)initiatedLocally
               andPotentiallySpecifiedContact:(Contact*)contact
                            andFutureAccepted:(TOCFuture*)futureCallLocallyAcceptedOrRejected {

    require(observableProgress != nil);
    require(futureTermination != nil);
    require(futureSas != nil);
    require(remoteNumber != nil);
    require(futureCallLocallyAcceptedOrRejected != nil);
    
    CallState* call = [CallState new];
    call->observableProgress = observableProgress;
    call->futureTermination = futureTermination;
    call->futureShortAuthenticationString = futureSas;
    call->remoteNumber = remoteNumber;
    call->initiatedLocally = initiatedLocally;
    call->potentiallySpecifiedContact = contact;
    call->futureCallLocallyAcceptedOrRejected = futureCallLocallyAcceptedOrRejected;
    return call;
}

@end
