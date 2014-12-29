#import "RecentCallManager.h"
#import "ContactsManager.h"
#import "FunctionalUtil.h"
#import "ObservableValue.h"
#import "PreferencesUtil.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSCall.h"
#import "TSStorageManager.h"
#import "TSContactThread.h"

@interface RecentCallManager ()
@property YapDatabaseConnection *dbConnection;
@end

@implementation RecentCallManager

- (instancetype)init{
    self = [super init];
    
    if (self) {
        _dbConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    }
    
    return self;
}

- (void)watchForCallsThrough:(PhoneManager*)phoneManager
              untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(phoneManager != nil);

    [phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall != nil) {
            [self addCall:latestCall];
        }
    } onThread:NSThread.currentThread untilCancelled:untilCancelledToken];
}

- (void)addCall:(CallState*)call {
    require(call != nil);
    
    [call.futureCallLocallyAcceptedOrRejected finallyDo:^(TOCFuture* interactionCompletion) {
        bool isOutgoingCall = call.initiatedLocally;
        bool isMissedCall = interactionCompletion.hasFailed;
        Contact* contact = [self tryGetContactForCall:call];
        
        RPRecentCallType callType = isOutgoingCall ? RPRecentCallTypeOutgoing
                                  : isMissedCall ? RPRecentCallTypeMissed
                                  : RPRecentCallTypeIncoming;
        
        [self addRecentCall:[RecentCall recentCallWithContactID:contact.recordID
                                                      andNumber:call.remoteNumber
                                                    andCallType:callType]];
    }];
}

- (Contact*)tryGetContactForCall:(CallState*)call {
    if (call.potentiallySpecifiedContact != nil) return call.potentiallySpecifiedContact;
    return [self tryGetContactForNumber:call.remoteNumber];
}

- (Contact*)tryGetContactForNumber:(PhoneNumber*)number {
    return [Environment.getCurrent.contactsManager latestContactForPhoneNumber:number];
}

- (void)addMissedCallDueToBusy:(ResponderSessionDescriptor*)incomingCallDescriptor {
    require(incomingCallDescriptor != nil);
    
    Contact* contact = [self tryGetContactForNumber:incomingCallDescriptor.initiatorNumber];
    [self addRecentCall:[RecentCall recentCallWithContactID:contact.recordID
                                                  andNumber:incomingCallDescriptor.initiatorNumber
                                                andCallType:RPRecentCallTypeMissed]];
}

- (void)addRecentCall:(RecentCall*)recentCall {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:recentCall.phoneNumber.toE164 transaction:transaction];
        TSCall *call = [[TSCall alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] withCallNumber:recentCall.phoneNumber.toE164 callType:recentCall.callType inThread:thread];
        [call saveWithTransaction:transaction];
    }];
}

@end
