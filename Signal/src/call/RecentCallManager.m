#import "RecentCallManager.h"
#import "ContactsManager.h"
#import "FunctionalUtil.h"
#import "ObservableValue.h"
#import "PreferencesUtil.h"


#define RECENT_CALLS_DEFAULT_KEY @"RPRecentCallsDefaultKey"

typedef BOOL (^SearchTermConditionalBlock)(RecentCall*, NSUInteger, BOOL*);

@interface RecentCallManager () {
    NSMutableArray *_allRecents;
}

@end

@implementation RecentCallManager

- (id)init {
    if (self = [super init]) {
        [self initRecentCallsObservable];
    }
    return self;
}

-(void) initRecentCallsObservable {
    _allRecents = [self loadContactsFromDefaults];
    observableRecentsController = [ObservableValueController observableValueControllerWithInitialValue:_allRecents];
}

- (ObservableValue *)getObservableRecentCalls {
    return observableRecentsController;
}

-(void) watchForContactUpdatesFrom:(ContactsManager*) contactManager untillCancelled:(TOCCancelToken*) cancelToken{
    [contactManager.getObservableRedPhoneUsers watchLatestValue:^(NSArray* latestUsers) {
        for (RecentCall* recentCall in _allRecents) {
            if (![contactManager latestContactWithRecordId:recentCall.contactRecordID]) {
                Contact* contact = [contactManager latestContactForPhoneNumber:recentCall.phoneNumber];
                if(contact){
                    [self updateRecentCall:recentCall withContactId:contact.recordID];
                }
            }
        }
    } onThread:NSThread.mainThread untilCancelled:cancelToken];
}

-(void) watchForCallsThrough:(PhoneManager*)phoneManager
              untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(phoneManager != nil);

    [phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall != nil && Environment.preferences.getHistoryLogEnabled) {
            [self addCall:latestCall];
        }
    } onThread:NSThread.mainThread untilCancelled:untilCancelledToken];
}

-(void) addCall:(CallState*)call {
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

-(Contact*) tryGetContactForCall:(CallState*)call {
    if (call.potentiallySpecifiedContact != nil) return call.potentiallySpecifiedContact;
    return [self tryGetContactForNumber:call.remoteNumber];
}

-(Contact*) tryGetContactForNumber:(PhoneNumber*)number {
    return [Environment.getCurrent.contactsManager latestContactForPhoneNumber:number];
}

- (void)addMissedCallDueToBusy:(ResponderSessionDescriptor*)incomingCallDescriptor {
    require(incomingCallDescriptor != nil);
    
    Contact* contact = [self tryGetContactForNumber:incomingCallDescriptor.initiatorNumber];
    [self addRecentCall:[RecentCall recentCallWithContactID:contact.recordID
                                                  andNumber:incomingCallDescriptor.initiatorNumber
                                                andCallType:RPRecentCallTypeMissed]];
}

-(void) updateRecentCall:(RecentCall*) recentCall withContactId:(ABRecordID) contactId {
    [recentCall updateRecentCallWithContactId:contactId];
    [observableRecentsController updateValue:_allRecents.copy];
    [self saveContactsToDefaults];
}

- (void)addRecentCall:(RecentCall *)recentCall {
    [_allRecents insertObject:recentCall atIndex:0];
    [Environment.preferences setFreshInstallTutorialsEnabled:NO];
    [observableRecentsController updateValue:_allRecents.copy];
    [self saveContactsToDefaults];
}

- (void)removeRecentCall:(RecentCall *)recentCall {
    [_allRecents removeObject:recentCall];
    [observableRecentsController updateValue:_allRecents.copy];
    [self saveContactsToDefaults];
}

- (void)archiveRecentCall:(RecentCall *)recentCall {
    NSUInteger indexOfRecent = [_allRecents indexOfObject:recentCall];
    recentCall.isArchived = YES;
    _allRecents[indexOfRecent] = recentCall;
    [self saveContactsToDefaults];
    [observableRecentsController updateValue:_allRecents.copy];
}

- (void)clearRecentCalls {
    [_allRecents removeAllObjects];
    [observableRecentsController updateValue:_allRecents.copy];
    [self saveContactsToDefaults];
}

- (void)saveContactsToDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *saveData = [NSKeyedArchiver archivedDataWithRootObject:_allRecents.copy];

    [defaults setObject:saveData forKey:RECENT_CALLS_DEFAULT_KEY];
    [defaults synchronize];
}

- (NSMutableArray *)loadContactsFromDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *encodedData = [defaults objectForKey:RECENT_CALLS_DEFAULT_KEY];
    id data = [NSKeyedUnarchiver unarchiveObjectWithData:encodedData];

    if(![data isKindOfClass:NSArray.class]) {
        return [NSMutableArray array];
    } else {
        return [NSMutableArray arrayWithArray:data];
    }
}

- (NSArray *)recentsForSearchString:(NSString *)optionalSearchString andExcludeArchived:(BOOL)excludeArchived {
    ContactsManager *contactsManager = Environment.getCurrent.contactsManager;
    SearchTermConditionalBlock searchBlock = ^BOOL(RecentCall *obj, NSUInteger idx, BOOL *stop) {
        BOOL nameMatchesSearch = YES;
        BOOL numberMatchesSearch = YES;
        
        if (optionalSearchString) {
            NSString *contactName = [contactsManager latestContactWithRecordId:obj.contactRecordID].fullName;
            nameMatchesSearch = [ContactsManager name:contactName matchesQuery:optionalSearchString];
            numberMatchesSearch = [ContactsManager phoneNumber:obj.phoneNumber matchesQuery:optionalSearchString];
        }
        
        if (excludeArchived) {
            return !obj.isArchived && (nameMatchesSearch || numberMatchesSearch);
        } else {
            return (nameMatchesSearch || numberMatchesSearch);
        }
    };

    NSIndexSet *newsFeedIndexes = [_allRecents indexesOfObjectsPassingTest:searchBlock];
    return [_allRecents objectsAtIndexes:newsFeedIndexes];
}

- (NSUInteger)missedCallCount {
    SearchTermConditionalBlock missedCallBlock = ^BOOL(RecentCall *recentCall, NSUInteger idx, BOOL *stop) {
        return !recentCall.userNotified;
    };

    return [[_allRecents indexesOfObjectsPassingTest:missedCallBlock] count];
}

-(BOOL) isPhoneNumberPresentInRecentCalls:(PhoneNumber*) phoneNumber {
    return [_allRecents any:^int(RecentCall* call) {
        return [call.phoneNumber resolvesInternationallyTo:phoneNumber];
    }];
}

@end
