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

- (void)watchForCallsThrough:(PhoneManager*)phoneManager
			  untilCancelled:(TOCCancelToken*)untilCancelledToken;

- (void)addRecentCall:(RecentCall *)recentCall;
- (void)addMissedCallDueToBusy:(ResponderSessionDescriptor*)incomingCallDescriptor;

-(void) migrateToVersion2Dot0;
@end
