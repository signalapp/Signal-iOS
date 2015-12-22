#import <TextSecureKit/TextSecureKitEnv.h>
#import "NotificationsManager.h"
#import "RecentCallManager.h"
#import "TSCall.h"
#import "TSMessagesManager.h"
#import "TSStorageManager.h"

@interface RecentCallManager ()
@property YapDatabaseConnection *dbConnection;
@end

@implementation RecentCallManager

- (instancetype)init {
    self = [super init];

    if (self) {
        _dbConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    }

    return self;
}

- (void)watchForCallsThrough:(PhoneManager *)phoneManager untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(phoneManager != nil);

    [phoneManager.currentCallObservable watchLatestValue:^(CallState *latestCall) {
      if (latestCall != nil) {
          [self addCall:latestCall];
      }
    }
                                                onThread:NSThread.currentThread
                                          untilCancelled:untilCancelledToken];
}

- (void)addCall:(CallState *)call {
    ows_require(call != nil);

    [call.futureTermination finallyDo:^(TOCFuture *interactionCompletion) {
      bool isOutgoingCall = call.initiatedLocally;
      bool isMissedCall   = [self isMissedCall:interactionCompletion];

      Contact *contact = [self tryGetContactForCall:call];

      RPRecentCallType callType =
          isOutgoingCall ? RPRecentCallTypeOutgoing : isMissedCall ? RPRecentCallTypeMissed : RPRecentCallTypeIncoming;

      [self addRecentCall:[RecentCall recentCallWithContactID:contact.recordID
                                                    andNumber:call.remoteNumber
                                                  andCallType:callType]];
    }];
}

- (BOOL)isMissedCall:(TOCFuture *)interactionCompletion {
    if ([interactionCompletion hasResult]) {
        if ([[interactionCompletion forceGetResult] isKindOfClass:[CallTermination class]]) {
            CallTermination *termination = (CallTermination *)interactionCompletion.forceGetResult;
            if (termination.type == CallTerminationType_HangupRemote) {
                return YES;
            }
        }
    }
    return NO;
}

- (Contact *)tryGetContactForCall:(CallState *)call {
    if (call.potentiallySpecifiedContact != nil)
        return call.potentiallySpecifiedContact;
    return [self tryGetContactForNumber:call.remoteNumber];
}

- (Contact *)tryGetContactForNumber:(PhoneNumber *)number {
    return [Environment.getCurrent.contactsManager latestContactForPhoneNumber:number];
}

- (void)addMissedCallDueToBusy:(ResponderSessionDescriptor *)incomingCallDescriptor {
    ows_require(incomingCallDescriptor != nil);

    Contact *contact = [self tryGetContactForNumber:incomingCallDescriptor.initiatorNumber];
    [self addRecentCall:[RecentCall recentCallWithContactID:contact.recordID
                                                  andNumber:incomingCallDescriptor.initiatorNumber
                                                andCallType:RPRecentCallTypeMissed]];
}

- (void)addRecentCall:(RecentCall *)recentCall {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSContactThread *thread =
          [TSContactThread getOrCreateThreadWithContactId:recentCall.phoneNumber.toE164 transaction:transaction];

      uint64_t callDateSeconds = (uint64_t)[recentCall.date timeIntervalSince1970];
      TSCall *call             = [[TSCall alloc] initWithTimestamp:callDateSeconds * 1000
                                        withCallNumber:recentCall.phoneNumber.toE164
                                              callType:recentCall.callType
                                              inThread:thread];
      if (recentCall.isArchived) { // for migration only from Signal versions with RedPhone only
          NSDate *date =
              [NSDate dateWithTimeIntervalSince1970:(callDateSeconds +
                                                     60)]; // archive has to happen in the future of the original call
          [thread archiveThreadWithTransaction:transaction referenceDate:date];
      }

      [call saveWithTransaction:transaction];

      NotificationsManager *manager = [TextSecureKitEnv sharedEnv].notificationsManager;
      [manager notifyUserForCall:call inThread:thread];
    }];
}


@end
