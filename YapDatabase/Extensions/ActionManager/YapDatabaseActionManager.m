#import "YapDatabaseActionManager.h"
#import "YapActionable.h"
#import "YapActionItem.h"
#import "YapActionItemPrivate.h"

#import "YapDatabaseView.h"
#import "YapDatabaseLogging.h"

#import "NSDate+YapDatabase.h"

#import <libkern/OSAtomic.h>

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@interface YapDatabaseActionManager ()
@property (atomic, assign, readwrite) BOOL hasInternet;
@end

@implementation YapDatabaseActionManager
{
	YapDatabaseConnection *databaseConnection;
	
	YapDatabaseView *view;
	NSString *viewName;
	
	NSMutableDictionary *actionItemsDict;
	
	dispatch_source_t timer;
	dispatch_queue_t timerQueue;
	BOOL timerSuspended;
	
	int isRegistered;
}

@synthesize reachability = _mustGoThroughAtomicProperty_reachability;
@synthesize hasInternet = _mustGoThroughAtomicGetter_hasInternet;

- (instancetype)init
{
	if ((self = [super init]))
	{
		actionItemsDict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)registerWithDatabase:(YapDatabase *)database usingName:(NSString *)name
{
	if (![self _preRegistration:database usingName:name]) return NO;
	
	BOOL ready = [database registerExtension:view withName:name connection:databaseConnection];
	
	[self _postRegistration:database result:ready];
	
	return ready;
}

- (void)asyncRegisterWithDatabase:(YapDatabase *)database
                        usingName:(NSString *)name
                  completionBlock:(void(^)(BOOL ready))completionBlock
{
	[self asyncRegisterWithDatabase:database
	                      usingName:name
	                completionQueue:NULL
	                completionBlock:completionBlock];
}

- (void)asyncRegisterWithDatabase:(YapDatabase *)database
                        usingName:(NSString *)name
                  completionQueue:(dispatch_queue_t)completionQueue
			      completionBlock:(void(^)(BOOL ready))completionBlock
{
	if (![self _preRegistration:database usingName:name])
	{
		if (completionBlock)
		{
			if (completionQueue == NULL)
				completionQueue = dispatch_get_main_queue();
			
			dispatch_async(completionQueue, ^{ @autoreleasepool {
				completionBlock(NO);
			}});
		}
		
		return;
	}
	
	[database asyncRegisterExtension:view
							withName:viewName
						  connection:databaseConnection
					 completionQueue:completionQueue
					 completionBlock:^(BOOL ready)
	{
		[self _postRegistration:database result:ready];
		
		if (completionBlock)
			completionBlock(ready);
	}];
}

- (BOOL)_preRegistration:(YapDatabase *)database usingName:(NSString *)name
{
	// Set atomic value.
	// If already set, then this instance is already registered.
	
	int const oldValue = 0;
	int const newValue = 1;
	
	if (!OSAtomicCompareAndSwapInt(oldValue, newValue, &isRegistered))
	{
		return NO;
	}
	
	// Create and configure databaseConnection
	
	databaseConnection = [database newConnection];
	databaseConnection.name = @"YapDatabaseActionManager";
	databaseConnection.metadataCacheEnabled = NO;
	
	if (databaseConnection == nil) return NO;
	
	// Create and configure view
	
	YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object)
	{
		if ([object conformsToProtocol:@protocol(YapActionable)])
		{
			BOOL hasActionItems = NO;
			
			if ([object respondsToSelector:@selector(hasYapActionItems)])
			{
				hasActionItems = [(id <YapActionable>)object hasYapActionItems];
			}
			else
			{
				NSArray<YapActionItem*> *actionItems = [(id <YapActionable>)object yapActionItems];
				hasActionItems = (actionItems.count > 0);
			}
			
			if (hasActionItems)
			{
				return @"";
			}
		}
        
		return nil; // exclude from view
	}];
	
	YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(YapDatabaseReadTransaction *transaction, NSString *group,
		    NSString *collection1, NSString *key1, id obj1,
            NSString *collection2, NSString *key2, id obj2)
	{
		NSDate* (^GetEarliestActionItemDate)(id <YapActionable> item);
		GetEarliestActionItemDate = ^NSDate *(id <YapActionable> item){
		
			NSDate *earliestActionItemDate = nil;
			
			if ([item respondsToSelector:@selector(earliestYapActionItemDate)])
			{
				earliestActionItemDate = [item earliestYapActionItemDate];
			}
			
			if (earliestActionItemDate == nil)
			{
				NSArray<YapActionItem*> *actionItems = [(id <YapActionable>)item yapActionItems];
				
				NSArray<YapActionItem*> *sorted = [actionItems sortedArrayUsingSelector:@selector(compare:)];
				earliestActionItemDate = [[sorted firstObject] date];
			}
			
			if (earliestActionItemDate == nil)
			{
				YDBLogWarn(@"Unable to determine earliestActionDate for item: %@", item);
				earliestActionItemDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
			}
			
			return earliestActionItemDate;
		};
		
		NSDate *actionDate1 = GetEarliestActionItemDate((id <YapActionable>)obj1);
		NSDate *actionDate2 = GetEarliestActionItemDate((id <YapActionable>)obj2);
		
		return [actionDate1 compare:actionDate2];
	}];
	
	view = [[YapDatabaseView alloc] initWithGrouping:grouping
	                                         sorting:sorting
	                                      versionTag:@"1"];
	
	viewName = [name copy];
	
	return YES;
}

- (void)_postRegistration:(YapDatabase *)database result:(BOOL)ready
{
	if (ready)
	{
		Reachability *reachability = self.reachability;
		if (reachability == nil)
		{
			reachability = [Reachability reachabilityForInternetConnection];
			self.reachability = reachability;
		}
		
		[reachability startNotifier]; // safe to be called multiple times
		self.hasInternet = reachability.isReachable;
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(reachabilityChanged:)
		                                             name:kReachabilityChangedNotification
		                                           object:reachability];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(databaseModified:)
		                                             name:YapDatabaseModifiedNotification
		                                           object:database];
		
		// We're all ready to go.
		// Start the engine !
		//
		[self checkForActions_init];
		
	}
	else // if (!ready)
	{
		// teardown instance variable
		
		databaseConnection = nil;
		view = nil;
		viewName = nil;
		
		// unset registration flag
		
		int const oldValue = 1;
		int const newValue = 0;
		
		(void)OSAtomicCompareAndSwapInt(oldValue, newValue, &isRegistered);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)databaseModified:(NSNotification *)notification
{
	// We can check to see if the changes had any impact on our views.
	// If not we can skip the unnecessary processing.
	
	if ([[databaseConnection ext:viewName] hasChangesForNotifications:@[ notification ]])
	{
		[self checkForActions_databaseModified:notification];
	}
}

- (void)reachabilityChanged:(NSNotification *)notification
{
	Reachability *reachability = self.reachability;
	if (reachability)
		self.hasInternet = reachability.isReachable;
	else
		self.hasInternet = YES; // safety net
	
	if (notification) {
		[self checkForActions_reachabilityChanged];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Designed to be run immediately after database registration.
**/
- (void)checkForActions_init
{
	YDBLogAutoTrace();
	
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[self updateActionItemsDictWithTransaction:transaction databaseModifiedNotification:nil];
		[self processActionItemsDictWithTransaction:transaction];
	}];
}

/**
 * Designed to be run when our timer fires.
 * That is, when the next scheduled YapActionItem is set to start/retry.
**/
- (void)checkForActions_timerFire
{
	YDBLogAutoTrace();
	
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// Remember: when a timer fires, this may indicate that our last YapActionItem has expired.
		// So it's important we check the database for more YapActionItems.
		
		[self updateActionItemsDictWithTransaction:transaction databaseModifiedNotification:nil];
		[self processActionItemsDictWithTransaction:transaction];
	}];
}

/**
 * Designed to be run when reachabilityChanged notification fires.
**/
- (void)checkForActions_reachabilityChanged
{
	YDBLogAutoTrace();
	
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// If it's just a reachability change, then there's no need to check the database.
		
		[self processActionItemsDictWithTransaction:transaction];
	}];
}

- (void)checkForActions_databaseModified:(NSNotification *)notification
{
	YDBLogAutoTrace();
	
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[self updateActionItemsDictWithTransaction:transaction databaseModifiedNotification:notification];
		[self processActionItemsDictWithTransaction:transaction];
	}];
}

/**
 * Populates/updates the actionItemsDict by enumerating the objects in the view,
 * and extracting their list of YapActionItems. The items are then sorted and placed into the actionItemsDict.
**/
- (void)updateActionItemsDictWithTransaction:(YapDatabaseReadTransaction *)transaction
                databaseModifiedNotification:(NSNotification *)dbModifiedNotification
{
	NSArray *dbNotifications = dbModifiedNotification ? @[ dbModifiedNotification ] : nil;
	NSDate *now = [NSDate date];
	
	NSMutableSet *collectionKeysNotChecked = [NSMutableSet setWithArray:actionItemsDict.allKeys];
	
	// STEP 1 of 2
	//
	// Enumerate the objects in the view,
	// at least until we find an object for which all YapActionItems are set to start in the future.
	
	{ // limit scope
		
		__block YapCollectionKey *collectionKey;
		
		NSUInteger count = [[transaction ext:viewName] numberOfItemsInGroup:@""];
		
		[[transaction ext:viewName] enumerateKeysAndObjectsInGroup:@""
		                                               withOptions:0
		                                                     range:NSMakeRange(0, count)
		                                                    filter:
		^BOOL(NSString *collection, NSString *key)
		{
			//
			// Filtering Block (allows us to skip object deserialzation for unneeded rows)
			//
			
			collectionKey = YapCollectionKeyCreate(collection, key);
			[collectionKeysNotChecked removeObject:collectionKey];
			
			if (dbNotifications == nil)
			{
				return YES; // process row
			}
			else
			{
				if ([databaseConnection hasChangeForKey:key inCollection:collection inNotifications:dbNotifications])
					return YES; // process row
				else
					return NO;  // skip row (no need to process since it hasn't changed)
			}
			
		} usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
			
			//
			// Processing Block
			//
			
			NSArray *actionItems = nil;
			if ([object conformsToProtocol:@protocol(YapActionable)])
			{
				actionItems = [(id <YapActionable>)object yapActionItems];
			}
			
			if ([actionItems count] == 0)
			{
				[actionItemsDict removeObjectForKey:collectionKey];
			}
			else
			{
				YDBLogVerbose(@"collection(%@) key(%@) actionItems: %@", collection, key, actionItems);
				
				NSArray *newActionItems = [self mergeUpdatedActionItems:actionItems forCollectionKey:collectionKey];
				
				if (dbNotifications == nil)
				{
					// There's no need to process every single object in the view.
					// That is, we don't have to have every single YapActionItem in memory.
					// If we know that an object has only YapActionItems in the future,
					// then we can request the YapActionItems at a later date.
					//
					// So the idea is, we can stop processing as soon as we find an object with only YapActionItems
					// in the future.
					
					YapActionItem *earliestActionItem = [newActionItems firstObject];
					if (![earliestActionItem isReadyToStartAtDate:now])
					{
						*stop = YES;
					}
				}
			}
		}];
		
	}
	
	// STEP 2 of 2:
	//
	// Process any objects that were already in the actionItemsDict, but which didn't get processed above.
	//
	// If there are any items in collectionKeysNotChecked,
	// then these represent objects in the database that may have been modified or deleted,
	// but which we didn't check during the enumeration of the view above.
	//
	// Example 1:
	// An object, which previously had associated YapActionItems, was deleted from the database.
	// Thus we didn't encounter the object during our enumeration above.
	// We should check on it now. And in doing so we'll discover it's been removed.
	// And thus we can remove it from our actionItemsDict.
	//
	// Example 2:
	// An object, which previously had associated YapActionItems, was modified in the database.
	// Previously, it had a YapActionItem that was ready to start.
	// But now, it only has YapActionItems that are in the future.
	// Thus, we stopped our enumeration before checking on that item.
	// So we'll process it now, and update our actionItemsDict accordingly.
	
	for (YapCollectionKey *ck in collectionKeysNotChecked)
	{
		id object = nil;
		id metadata = nil;
		[transaction getObject:&object metadata:&metadata forKey:ck.key inCollection:ck.collection];
		
		NSArray *actionItems = nil;
		if ([object conformsToProtocol:@protocol(YapActionable)])
		{
			actionItems = [(id <YapActionable>)object yapActionItems];
		}
		
		if ([actionItems count] == 0)
		{
			[actionItemsDict removeObjectForKey:ck];
		}
		else
		{
			[self mergeUpdatedActionItems:actionItems forCollectionKey:ck];
		}
	}
	
	YDBLogVerbose(@"actionItemsDict: %@", actionItemsDict);
}

/**
 * Helper method for updateActionItemsDictWithTransaction:databaseModifiedNotification:
 *
 * Given an array of YapActionItems (just extracted from a YapActionable object),
 * this method merges each YapActionItem with its previous matching YapActionItem (if possible),
 * before placing the items into the actionItemsDict.
 * 
 * By "merge" what we mean is merging the following (internal) properties:
 * - YapActionItem.isStarted
 * - YapActionItem.isPendingInternet
 * - YapActionItem.nextRetry
 *
 * @return The sorted & merged actionItems.
**/
- (NSArray *)mergeUpdatedActionItems:(NSArray *)inActionItems forCollectionKey:(YapCollectionKey *)collectionKey
{
	// Step 1 of 4:
	//
	// Make COPIES of each YapActionItem
	
	NSArray *unsortedActionItems = [[NSArray alloc] initWithArray:inActionItems copyItems:YES];
	
	// Step 2 of 4:
	//
	// Sort the actionItems by date.
	
	NSArray *newActionItems = [unsortedActionItems sortedArrayUsingSelector:@selector(compare:)];
	
	// Step 3 of 4:
	//
	// Some of the actionItems may be duplicates of what we already have.
	// Here's how it works:
	//
	// If two YapActionItems have the same identifier & date, then they are considered "equal".
	// If they have different identifiers, then they are for completely separate tasks.
	// If they have different dates, then the new date is considered a different task.
	//
	// In other words, when the date changes, then the task is different in the sense that
	// the user has requested it to be run again at another time.
	// For example, a refresh task may be run every few days/hours in order to refresh info from a web server.
	// Thus, when a refresh finishes, it will create another YapActionItem with the same identifier but later date.
	// This represents a new YapActionItem, and the previous YapActionItem should be considered complete.
	
	NSArray *oldActionItems = [actionItemsDict objectForKey:collectionKey];
	
	YapActionItem *(^FindMatchingOldActionItem)(YapActionItem *newActionItem);
	FindMatchingOldActionItem = ^YapActionItem *(YapActionItem *newActionItem){
		
		YapActionItem *matchingOldActionItem = nil;
		
		for (YapActionItem *oldActionItem in oldActionItems)
		{
			if ([oldActionItem hasSameIdentifierAndDate:newActionItem])
			{
				matchingOldActionItem = oldActionItem;
				break;
			}
		}
		
		return matchingOldActionItem;
	};
	
	for (YapActionItem *newActionItem in newActionItems)
	{
		YapActionItem *matchingOldActionItem = FindMatchingOldActionItem(newActionItem);
		if (matchingOldActionItem)
		{
			newActionItem.isStarted         = matchingOldActionItem.isStarted;
			newActionItem.isPendingInternet = matchingOldActionItem.isPendingInternet;
			newActionItem.nextRetry         = matchingOldActionItem.nextRetry;
		}
		else
		{
			newActionItem.isStarted = NO;
			newActionItem.isPendingInternet = NO;
			newActionItem.nextRetry = nil;
		}
	}
	
	// Step 4 of 4:
	//
	// Put the actionItems array into the actionItemsDict.
	
	[actionItemsDict setObject:newActionItems forKey:collectionKey];
	
	return newActionItems;
}

/**
 * Process each YapctionItem, starting/retrying them if needed.
 * And then start a timer to fire for the next pending YapActionItem.
**/
- (void)processActionItemsDictWithTransaction:(YapDatabaseReadTransaction *)transaction
{
	YDBLogAutoTrace();
	
	NSDate *now = [NSDate date];
	BOOL hasInternet = self.hasInternet;
	
	__block NSMutableArray *collectionKeysToRemove = nil;
	__block NSDate *nextTimerFireDate = nil;
	
	[actionItemsDict enumerateKeysAndObjectsUsingBlock:^(YapCollectionKey *ck, NSArray *actionItems, BOOL *stop) {
		
		[actionItems enumerateObjectsUsingBlock:^(YapActionItem *actionItem, NSUInteger idx, BOOL *stop) {
			
			BOOL needsRun = NO;
			NSDate *actionDate = nil;
			
			//
			// <YapActionItem Run Logic>
			//
			if (actionItem.isStarted == NO)
			{
				// The actionItem has never been started.
				
				if ([actionItem isReadyToStartAtDate:now])
				{
					if (!actionItem.requiresInternet || hasInternet)
						needsRun = YES;                         // start it
					else
						actionItem.isPendingInternet = YES;     // need to wait for internet before starting
				}
				else
				{
					actionDate = actionItem.date;               // need to wait til date before starting
				}
			}
			else if (actionItem.isPendingInternet)
			{
				// The actionItem has been run at least once. (actionItem.isStarted == YES)
				// The actionItem is ready to be restarted, as soon as internet becomes available.
				
				needsRun = hasInternet;                         // restart it if internet is available
			}
			else if (actionItem.nextRetry)
			{
				// The actionItem has been run at least once. (actionItem.isStarted == YES)
				// It's configured with a retryTimeout, in order to run multiple times (if needed).
				
				if ([actionItem isReadyToRetryAtDate:now])
				{
					if (!actionItem.requiresInternet || hasInternet)
						needsRun = YES;                         // restart it
					else
						actionItem.isPendingInternet = YES;     // need to wait for internet before restarting
				}
				else
				{
					actionDate = actionItem.nextRetry;          // need to wait til nextRetry date before restarting
				}
			}
			//
			// </YapActionItem Run Logic>
			//
			
			if (needsRun)
			{
				YDBLogVerbose(@"%@ actionItem: collection(%@) key(%@) identifier(%@)",
				              (actionItem.isStarted ? @"Retrying" : @"Starting"),
				              ck.collection, ck.key, actionItem.identifier);
				
				id object = nil;
				id metadata = nil;
				[transaction getObject:&object metadata:&metadata forKey:ck.key inCollection:ck.collection];
				
				if (object == nil)
				{
					// The object is no longer in the database.
					//
					// This is a race condition.
					// Basically, we're processing a timerFire or reachabilityChange notification
					// prior to a databaseModified notification. So we're just a bit out of date.
					//
					// No worries. We just queue the associated YapActionItems to be removed.
					
					if (collectionKeysToRemove == nil)
						collectionKeysToRemove = [NSMutableArray array];
					
					[collectionKeysToRemove addObject:ck];
					
					actionDate = nil;
				}
				else
				{
					dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
					dispatch_async(bgQueue, ^{
						
						actionItem.block(ck.collection, ck.key, object, metadata);
					});
					
					actionItem.isStarted = YES;
					actionItem.isPendingInternet = NO;
					
					if (actionItem.retryTimeout > 0.0) {
						actionItem.nextRetry = [now dateByAddingTimeInterval:actionItem.retryTimeout];
						actionDate = actionItem.nextRetry; // <- Important
					}
				}
			}
			
			// actionDate will be:
			// - actionItem.date if not started and not pendingInternet
			// - actionItem.nextRetry if set
			// - nil otherwise
			
			if (actionDate)
			{
				if (nextTimerFireDate == nil)
					nextTimerFireDate = actionDate;
				else
					nextTimerFireDate = [nextTimerFireDate earlierDate:actionDate];
			}
		}];
	}];
	
	if (collectionKeysToRemove)
	{
		[actionItemsDict removeObjectsForKeys:collectionKeysToRemove];
	}
	
	[self updateTimerWithDate:nextTimerFireDate];
}

/**
 * This method is expected to be run within [databaseConnection readWithBlock:].
**/
- (void)updateTimerWithDate:(NSDate *)nextFireDate
{
	YDBLogAutoTrace();
	
	if (timer == NULL)
	{
		timerQueue = dispatch_queue_create("DatabaseActionManager-timer", DISPATCH_QUEUE_SERIAL);
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
		
		__weak YapDatabaseActionManager *weakSelf = self;
		dispatch_source_set_event_handler(timer, ^{
			
			__strong YapDatabaseActionManager *strongSelf = weakSelf;
			
			[strongSelf checkForActions_timerFire];
		});
		
		timerSuspended = YES;
	}
	
	if (nextFireDate)
	{
		NSTimeInterval startOffset = [nextFireDate timeIntervalSinceNow];
		if (startOffset < 0.0)
			startOffset = 0.0;
		
		dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (startOffset * NSEC_PER_SEC));
		
		uint64_t interval = DISPATCH_TIME_FOREVER;
		uint64_t leeway = (0.1 * NSEC_PER_SEC);
		
		dispatch_source_set_timer(timer, start, interval, leeway);
		
		if (timerSuspended) {
			dispatch_resume(timer);
			timerSuspended = NO;
		}
	}
	else
	{
		if (!timerSuspended) {
			dispatch_suspend(timer);
			timerSuspended = YES;
		}
	}
}

@end
