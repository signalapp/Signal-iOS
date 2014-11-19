#import <Foundation/Foundation.h>
#import "RecentCall.h"
#import "PhoneManager.h"

/**
 *
 * RecentCallManager is used for adding and reading RecentCall objects from NSUserDefaults.
 * Recent Call objects that are non-archived are to be displayed in the Inbox and persist in RecentCallViewController.
 * This class also contains an observable value that can be subscribed to which gives updates.
 *
 */

@interface RecentCallManager : NSObject

- (instancetype)init;

- (ObservableValue*)getObservableRecentCalls;
- (void)watchForCallsThrough:(PhoneManager*)phoneManager untilCancelled:(TOCCancelToken*)untilCancelledToken;
- (void)watchForContactUpdatesFrom:(ContactsManager*)contactManager untillCancelled:(TOCCancelToken*)cancelToken;

- (void)addRecentCall:(RecentCall*)recentCall;
- (void)removeRecentCall:(RecentCall*)recentCall;
- (void)archiveRecentCall:(RecentCall*)recentCall;
- (void)clearRecentCalls;
- (void)addMissedCallDueToBusy:(ResponderSessionDescriptor*)incomingCallDescriptor;
- (NSArray*)recentsForSearchString:(NSString*)optionalSearchString
                andExcludeArchived:(BOOL)excludeArchived;
- (void)saveContactsToDefaults;
- (BOOL)isPhoneNumberPresentInRecentCalls:(PhoneNumber*)phoneNumber;
- (NSUInteger)missedCallCount;

@end
