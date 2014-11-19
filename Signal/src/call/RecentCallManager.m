#import "RecentCallManager.h"
#import "ContactsManager.h"
#import "NSArray+FunctionalUtil.h"
#import "ObservableValue.h"
#import "PropertyListPreferences+Util.h"


#define RECENT_CALLS_DEFAULT_KEY @"RPRecentCallsDefaultKey"

typedef BOOL (^SearchTermConditionalBlock)(RecentCall*, NSUInteger, BOOL*);

@interface RecentCallManager ()

@property (strong, nonatomic) NSMutableArray* allRecents;
@property (strong, nonatomic) ObservableValueController* observableRecentsController;

@end

@implementation RecentCallManager

- (instancetype)init {
    if (self = [super init]) {
        self.allRecents = [self loadContactsFromDefaults];
        self.observableRecentsController = [[ObservableValueController alloc] initWithInitialValue:self.allRecents];
    }
    
    return self;
}

- (ObservableValue*)getObservableRecentCalls {
    return self.observableRecentsController;
}

- (void)watchForContactUpdatesFrom:(ContactsManager*)contactManager untillCancelled:(TOCCancelToken*)cancelToken {
    [contactManager.getObservableWhisperUsers watchLatestValue:^(NSArray* latestUsers) {
        for (RecentCall* recentCall in self.allRecents) {
            if (![contactManager latestContactWithRecordId:recentCall.contactRecordID]) {
                Contact* contact = [contactManager latestContactForPhoneNumber:recentCall.phoneNumber];
                if (contact) {
                    [self updateRecentCall:recentCall withContactId:contact.recordID];
                }
            }
        }
    } onThread:[NSThread mainThread] untilCancelled:cancelToken];
}

- (void)watchForCallsThrough:(PhoneManager*)phoneManager untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(phoneManager != nil);

    [phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall != nil && Environment.preferences.getHistoryLogEnabled) {
            [self addCall:latestCall];
        }
    } onThread:[NSThread mainThread] untilCancelled:untilCancelledToken];
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
        
        [self addRecentCall:[[RecentCall alloc] initWithContactID:contact.recordID
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
    [self addRecentCall:[[RecentCall alloc] initWithContactID:contact.recordID
                                                    andNumber:incomingCallDescriptor.initiatorNumber
                                                  andCallType:RPRecentCallTypeMissed]];
}

- (void)updateRecentCall:(RecentCall*)recentCall withContactId:(ABRecordID)contactId {
    [recentCall updateRecentCallWithContactID:contactId];
    [self.observableRecentsController updateValue:[self.allRecents copy]];
    [self saveContactsToDefaults];
}

- (void)addRecentCall:(RecentCall*)recentCall {
    [self.allRecents insertObject:recentCall atIndex:0];
    [Environment.preferences setFreshInstallTutorialsEnabled:NO];
    [self.observableRecentsController updateValue:[self.allRecents copy]];
    [self saveContactsToDefaults];
}

- (void)removeRecentCall:(RecentCall*)recentCall {
    [self.allRecents removeObject:recentCall];
    [self.observableRecentsController updateValue:[self.allRecents copy]];
    [self saveContactsToDefaults];
}

- (void)archiveRecentCall:(RecentCall*)recentCall {
    NSUInteger indexOfRecent = [self.allRecents indexOfObject:recentCall];
    recentCall.isArchived = YES;
    self.allRecents[indexOfRecent] = recentCall;
    [self saveContactsToDefaults];
    [self.observableRecentsController updateValue:[self.allRecents copy]];
}

- (void)clearRecentCalls {
    [_allRecents removeAllObjects];
    [self.observableRecentsController updateValue:[self.allRecents copy]];
    [self saveContactsToDefaults];
}

- (void)saveContactsToDefaults {
    NSData *saveData = [NSKeyedArchiver archivedDataWithRootObject:[self.allRecents copy]];

    [[NSUserDefaults standardUserDefaults] setObject:saveData forKey:RECENT_CALLS_DEFAULT_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSMutableArray*)loadContactsFromDefaults {
    NSData *encodedData = [[NSUserDefaults standardUserDefaults] objectForKey:RECENT_CALLS_DEFAULT_KEY];
    id data = [NSKeyedUnarchiver unarchiveObjectWithData:encodedData];

    if (![data isKindOfClass:[NSArray class]]) {
        return [[NSMutableArray alloc] init];
    } else {
        return [NSMutableArray arrayWithArray:data];
    }
}

- (NSArray*)recentsForSearchString:(NSString*)optionalSearchString andExcludeArchived:(BOOL)excludeArchived {
    ContactsManager* contactsManager = Environment.getCurrent.contactsManager;
    SearchTermConditionalBlock searchBlock = ^BOOL(RecentCall* obj, NSUInteger idx, BOOL* stop) {
        BOOL nameMatchesSearch = YES;
        BOOL numberMatchesSearch = YES;
        
        if (optionalSearchString) {
            NSString* contactName = [contactsManager latestContactWithRecordId:obj.contactRecordID].fullName;
            nameMatchesSearch = [ContactsManager name:contactName matchesQuery:optionalSearchString];
            numberMatchesSearch = [ContactsManager phoneNumber:obj.phoneNumber matchesQuery:optionalSearchString];
        }
        
        if (excludeArchived) {
            return !obj.isArchived && (nameMatchesSearch || numberMatchesSearch);
        } else {
            return (nameMatchesSearch || numberMatchesSearch);
        }
    };

    NSIndexSet *newsFeedIndexes = [self.allRecents indexesOfObjectsPassingTest:searchBlock];
    return [self.allRecents objectsAtIndexes:newsFeedIndexes];
}

- (NSUInteger)missedCallCount {
    SearchTermConditionalBlock missedCallBlock = ^BOOL(RecentCall* recentCall, NSUInteger idx, BOOL* stop) {
        return !recentCall.userNotified;
    };

    return [[self.allRecents indexesOfObjectsPassingTest:missedCallBlock] count];
}

- (BOOL)isPhoneNumberPresentInRecentCalls:(PhoneNumber*)phoneNumber {
    return [self.allRecents any:^int(RecentCall* call) {
        return [call.phoneNumber resolvesInternationallyTo:phoneNumber];
    }];
}

@end
