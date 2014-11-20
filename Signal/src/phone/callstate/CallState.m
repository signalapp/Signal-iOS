#import "CallState.h"
#import "Util.h"

@interface CallState ()

@property (strong, nonatomic, readwrite) ObservableValue* observableProgress;
@property (strong, nonatomic, readwrite) TOCFuture* futureTermination;
@property (strong, nonatomic, readwrite) TOCFuture* futureShortAuthenticationString;
@property (strong, nonatomic, readwrite) PhoneNumber* remoteNumber;
@property (strong, nonatomic, readwrite) Contact* potentiallySpecifiedContact;
@property (strong, nonatomic, readwrite) TOCFuture* futureCallLocallyAcceptedOrRejected;
@property (nonatomic, readwrite) bool initiatedLocally;

@end

@implementation CallState

- (instancetype)initWithObservableProgress:(ObservableValue*)observableProgress
                      andFutureTermination:(TOCFuture*)futureTermination
                              andFutureSas:(TOCFuture*)futureSas
                           andRemoteNumber:(PhoneNumber*)remoteNumber
                       andInitiatedLocally:(bool)initiatedLocally
            andPotentiallySpecifiedContact:(Contact*)contact
                         andFutureAccepted:(TOCFuture*)futureCallLocallyAcceptedOrRejected {
    self = [super init];
	
    if (self) {
        require(observableProgress != nil);
        require(futureTermination != nil);
        require(futureSas != nil);
        require(remoteNumber != nil);
        require(futureCallLocallyAcceptedOrRejected != nil);
        
        self.observableProgress = observableProgress;
        self.futureTermination = futureTermination;
        self.futureShortAuthenticationString = futureSas;
        self.remoteNumber = remoteNumber;
        self.initiatedLocally = initiatedLocally;
        self.potentiallySpecifiedContact = contact;
        self.futureCallLocallyAcceptedOrRejected = futureCallLocallyAcceptedOrRejected;
    }
    
    return self;
}

@end
