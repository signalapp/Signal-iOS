#import "CloudKitManager.h"
#import "DatabaseManager.h"
#import "AppDelegate.h"
#import "MyTodo.h"
#import "DDLog.h"

#import <CloudKit/CloudKit.h>
#import <Reachability/Reachability.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif

CloudKitManager *MyCloudKitManager;

static NSString *const Key_HasZone             = @"hasZone";
static NSString *const Key_HasZoneSubscription = @"hasZoneSubscription";
static NSString *const Key_ServerChangeToken   = @"serverChangeToken";

@interface CloudKitManager ()

// Initial setup
@property (atomic, readwrite) BOOL needsCreateZone;
@property (atomic, readwrite) BOOL needsCreateZoneSubscription;
@property (atomic, readwrite) BOOL needsFetchRecordChangesAfterAppLaunch;

// Error handling
@property (atomic, readwrite) BOOL needsResume;
@property (atomic, readwrite) BOOL needsFetchRecordChanges;
@property (atomic, readwrite) BOOL needsRefetchMissedRecordIDs;

@property (atomic, readwrite) BOOL lastSuccessfulFetchResultWasNoData;

@end

@implementation CloudKitManager
{
	YapDatabaseConnection *databaseConnection;
	dispatch_queue_t fetchQueue;
	
	NSString *lastChangeSetUUID;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		MyCloudKitManager = [[CloudKitManager alloc] init];
	});
}

+ (instancetype)sharedInstance
{
	return MyCloudKitManager;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)init
{
	NSAssert(MyCloudKitManager == nil, @"Must use sharedInstance singleton (global MyCloudKitManager)");
	
	if ((self = [super init]))
	{
		// We could create our own dedicated databaseConnection.
		// But our needs are pretty basic, so we're just going to use the generic background connection.
		databaseConnection = MyDatabaseManager.bgDatabaseConnection;
		
		fetchQueue = dispatch_queue_create("CloudKitManager.fetchQueue", DISPATCH_QUEUE_SERIAL);
		
		self.needsCreateZone = YES;
		self.needsCreateZoneSubscription = YES;
		self.needsFetchRecordChangesAfterAppLaunch = YES;
		
		[self configureCloudKit];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(applicationDidEnterBackground:)
		                                             name:UIApplicationDidEnterBackgroundNotification
		                                           object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(applicationWillEnterForeground:)
		                                             name:UIApplicationWillEnterForegroundNotification
		                                           object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(cloudKitInFlightChangeSetChanged:)
	                                             name:YapDatabaseCloudKitInFlightChangeSetChangedNotification
	                                           object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(reachabilityChanged:)
		                                             name:kReachabilityChangedNotification
		                                           object:nil];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark App Launch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)configureCloudKit
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		if ([transaction hasObjectForKey:Key_HasZone inCollection:Collection_CloudKit]) {
			self.needsCreateZone = NO;
		}
		if ([transaction hasObjectForKey:Key_HasZoneSubscription inCollection:Collection_CloudKit]) {
			self.needsCreateZoneSubscription = NO;
		}
	}];
	
	//
	// Create CKRecordZone (if needed)
	//
	
	CKModifyRecordZonesOperation *modifyRecordZonesOperation = nil;
	
	void (^ContinueAfterCreateZone)(BOOL updateDatabase) = ^(BOOL updateDatabase){
		
		// Create zone complete.
		// Decrement suspend count.
		[MyDatabaseManager.cloudKitExtension resume];
		
		// Unflag property
		self.needsCreateZone = NO;
		
		if (updateDatabase)
		{
			// Put flag in database so we know we can skip this operation next time
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction setObject:@(YES) forKey:Key_HasZone inCollection:Collection_CloudKit];
			}];
		}
	};
	
	if (self.needsCreateZone)
	{
		CKRecordZone *recordZone = [[CKRecordZone alloc] initWithZoneName:CloudKitZoneName];
		
		modifyRecordZonesOperation =
		  [[CKModifyRecordZonesOperation alloc] initWithRecordZonesToSave:@[ recordZone ]
		                                            recordZoneIDsToDelete:nil];
		
		modifyRecordZonesOperation.modifyRecordZonesCompletionBlock =
		^(NSArray *savedRecordZones, NSArray *deletedRecordZoneIDs, NSError *operationError)
		{
			if (operationError)
			{
				DDLogError(@"Error creating zone: %@", operationError);
			}
			else
			{
				DDLogInfo(@"Successfully created zones: %@", savedRecordZones);
				
				self.needsCreateZone = NO;
				
				BOOL shouldUpdateDatabase = YES;
				ContinueAfterCreateZone(shouldUpdateDatabase);
			}
		};
		
		[[[CKContainer defaultContainer] privateCloudDatabase] addOperation:modifyRecordZonesOperation];
	}
	else
	{
		BOOL shouldUpdateDatabase = NO;
		ContinueAfterCreateZone(shouldUpdateDatabase);
	}
	
	//
	// Create CKSubscription (if needed)
	//
	
	CKModifySubscriptionsOperation *modifySubscriptionsOperation = nil;
	
	void (^ContinueAfterCreateZoneSubscription)(BOOL updateDatabase) = ^(BOOL updateDatabase) {
		
		// Create zone subscription complete.
		// Decrement suspend count.
		[MyDatabaseManager.cloudKitExtension resume];
		
		if (updateDatabase)
		{
			// Put flag in database so we know we can skip this operation next time
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction setObject:@(YES) forKey:Key_HasZoneSubscription inCollection:Collection_CloudKit];
			}];
		}
		
		// We're ready for the initial fetchRecordChanges post app-launch.
		[self fetchRecordChangesAfterAppLaunch];
	};
	
	if (self.needsCreateZoneSubscription)
	{
		CKRecordZoneID *recordZoneID =
		  [[CKRecordZoneID alloc] initWithZoneName:CloudKitZoneName ownerName:CKOwnerDefaultName];
		
		CKSubscription *subscription =
		  [[CKSubscription alloc] initWithZoneID:recordZoneID subscriptionID:CloudKitZoneName options:0];
		
		modifySubscriptionsOperation =
		  [[CKModifySubscriptionsOperation alloc] initWithSubscriptionsToSave:@[ subscription ]
		                                              subscriptionIDsToDelete:nil];
		
		modifySubscriptionsOperation.modifySubscriptionsCompletionBlock =
		^(NSArray *savedSubscriptions, NSArray *deletedSubscriptionIDs, NSError *operationError)
		{
			if (operationError)
			{
				DDLogError(@"Error creating subscription: %@", operationError);
			}
			else
			{
				DDLogInfo(@"Successfully created subscription: %@", savedSubscriptions);
				
				self.needsCreateZoneSubscription = NO;
				
				BOOL shouldUpdateDatabase = YES;
				ContinueAfterCreateZoneSubscription(shouldUpdateDatabase);
			}
		};
		
		if (modifyRecordZonesOperation) {
			[modifySubscriptionsOperation addDependency:modifyRecordZonesOperation];
		}
		
		[[[CKContainer defaultContainer] privateCloudDatabase] addOperation:modifySubscriptionsOperation];
	}
	else
	{
		BOOL shouldUpdateDatabase = NO;
		ContinueAfterCreateZoneSubscription(shouldUpdateDatabase);
	}
}

/**
 * This method is invoked after the CKRecordZone & CKSubscription are setup.
**/
- (void)fetchRecordChangesAfterAppLaunch
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	if (self.needsFetchRecordChangesAfterAppLaunch == NO) return;
	
	[self fetchRecordChangesWithCompletionHandler:^(UIBackgroundFetchResult result, BOOL moreComing) {
		
		if ((result != UIBackgroundFetchResultFailed) && !moreComing)
		{
			self.needsFetchRecordChangesAfterAppLaunch = NO;
			
			// Initial fetchRecordChanges operation complete.
			// Decrement suspend count.
			[MyDatabaseManager.cloudKitExtension resume];
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Fetching
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method uses CKFetchRecordChangesOperation to fetch changes.
 * It continues fetching until its reported that we're caught up.
 *
 * This method is invoked once automatically, when the CloudKitManager is initialized.
 * After that, one should invoke it anytime a corresponding push notification is received.
**/
- (void)fetchRecordChangesWithCompletionHandler:
        (void (^)(UIBackgroundFetchResult result, BOOL moreComing))completionHandler
{
	dispatch_async(fetchQueue, ^{ @autoreleasepool {
	
		[self _fetchRecordChangesWithCompletionHandler:completionHandler];
	}});
}

- (void)_fetchRecordChangesWithCompletionHandler:
        (void (^)(UIBackgroundFetchResult result, BOOL moreComing))completionHandler
{
	// Suspend the fetchQueue.
	// We will resume it upon completion of the fetchRecordsOperation.
	// This ensures that there is only one outstanding fetchRecordsOperation at a time.
	dispatch_suspend(fetchQueue);
	
	__block CKServerChangeToken *prevServerChangeToken = nil;
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		prevServerChangeToken = [transaction objectForKey:Key_ServerChangeToken inCollection:Collection_CloudKit];
		
	} completionBlock:^{
		
		[self _fetchRecordChangesWithPrevServerChangeToken:prevServerChangeToken
		                                 completionHandler:completionHandler];
	}];
}

- (void)_fetchRecordChangesWithPrevServerChangeToken:(CKServerChangeToken *)prevServerChangeToken
								  completionHandler:
        (void (^)(UIBackgroundFetchResult result, BOOL moreComing))completionHandler
{
	CKRecordZoneID *recordZoneID =
	  [[CKRecordZoneID alloc] initWithZoneName:CloudKitZoneName ownerName:CKOwnerDefaultName];
	
	CKFetchRecordChangesOperation *operation =
	  [[CKFetchRecordChangesOperation alloc] initWithRecordZoneID:recordZoneID
	                                    previousServerChangeToken:prevServerChangeToken];
	
	__block NSMutableArray *deletedRecordIDs = nil;
	__block NSMutableArray *changedRecords = nil;
	
	operation.recordWithIDWasDeletedBlock = ^(CKRecordID *recordID){
		
		if (deletedRecordIDs == nil)
			deletedRecordIDs = [[NSMutableArray alloc] init];
		
		[deletedRecordIDs addObject:recordID];
	};
	
	operation.recordChangedBlock = ^(CKRecord *record){
		
		if (changedRecords == nil)
			changedRecords = [[NSMutableArray alloc] init];
		
		[changedRecords addObject:record];
	};
	
	__weak CKFetchRecordChangesOperation *weakOperation = operation;
	operation.fetchRecordChangesCompletionBlock =
	^(CKServerChangeToken *newServerChangeToken, NSData *clientChangeTokenData, NSError *operationError){
		
		DDLogVerbose(@"CKFetchRecordChangesOperation.fetchRecordChangesCompletionBlock");
		
		DDLogVerbose(@"CKFetchRecordChangesOperation: serverChangeToken: %@", newServerChangeToken);
		DDLogVerbose(@"CKFetchRecordChangesOperation: clientChangeTokenData: %@", clientChangeTokenData);
		
		BOOL hasChanges = NO;
		if (!operationError)
		{
			if (deletedRecordIDs.count > 0)
				hasChanges = YES;
			else if (changedRecords.count > 0)
				hasChanges = YES;
			
			self.lastSuccessfulFetchResultWasNoData = (hasChanges == NO);
		}
		
		if (operationError)
		{
			// I've seen:
			//
			// - CKErrorNotAuthenticated - "CloudKit access was denied by user settings"; Retry after 3.0 seconds
			
			DDLogError(@"CKFetchRecordChangesOperation: operationError: %@", operationError);
			
			dispatch_resume(fetchQueue);
			if (completionHandler) {
				completionHandler(UIBackgroundFetchResultFailed, NO);
			}
		}
		else if (!hasChanges)
		{
			// Just to be safe, we're going to go ahead and save the newServerChangeToken.
			//
			// By the way:
			// - The CKServerChangeToken class has no API
			// - Comparing two serverChangeToken's via isEqual doesn't work
			// - Archiving two serverChangeToken's into NSData, and comparing that doesn't work either
			
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction setObject:newServerChangeToken
				                forKey:Key_ServerChangeToken
				          inCollection:Collection_CloudKit];
			}];
			
			dispatch_resume(fetchQueue);
			if (completionHandler) {
				completionHandler(UIBackgroundFetchResultNoData, NO);
			}
		}
		else // if (hasChanges)
		{
			BOOL moreComing = weakOperation.moreComing;
			
			DDLogVerbose(@"CKFetchRecordChangesOperation: deletedRecordIDs: %@", deletedRecordIDs);
			DDLogVerbose(@"CKFetchRecordChangesOperation: changedRecords: %@", changedRecords);
			
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				// Remove the items that were deleted (by another device)
				for (CKRecordID *recordID in deletedRecordIDs)
				{
					NSArray *collectionKeys =
					  [[transaction ext:Ext_CloudKit] collectionKeysForRecordID:recordID
					                                         databaseIdentifier:nil];
					
					for (YapCollectionKey *ck in collectionKeys)
					{
						// This MUST go FIRST
						[[transaction ext:Ext_CloudKit] detachRecordForKey:ck.key
						                                      inCollection:ck.collection
						                                 wasRemoteDeletion:YES
						                              shouldUploadDeletion:NO];
						
						// This MUST go SECOND
						[transaction removeObjectForKey:ck.key inCollection:ck.collection];
					}
				}
				
				// Update the items that were modified (by another device)
				for (CKRecord *record in changedRecords)
				{
					if (![record.recordType isEqualToString:@"todo"])
					{
						// Ignore unknown record types.
						// These are probably from a future version that this version doesn't support.
						continue;
					}
					
					BOOL requiresMerge = NO;
					BOOL exists = [[transaction ext:Ext_CloudKit] containsRecordID:record.recordID
					                                            databaseIdentifier:nil
					                                                 pendingDelete:&requiresMerge];
					
					if (exists || requiresMerge)
					{
						[[transaction ext:Ext_CloudKit] mergeRecord:record databaseIdentifier:nil];
					}
					else
					{
						MyTodo *newTodo = [[MyTodo alloc] initWithRecord:record];
						
						NSString *key = newTodo.uuid;
						NSString *collection = Collection_Todos;
						
						// This MUST go FIRST
						[[transaction ext:Ext_CloudKit] attachRecord:record
						                          databaseIdentifier:nil
						                                      forKey:key
						                                inCollection:collection
						                          shouldUploadRecord:NO];
						
						// This MUST go SECOND
						[transaction setObject:newTodo forKey:newTodo.uuid inCollection:Collection_Todos];
					}
				}
				
				// And save the serverChangeToken (in the same atomic transaction)
				[transaction setObject:newServerChangeToken
				                forKey:Key_ServerChangeToken
				          inCollection:Collection_CloudKit];
				
			} completionBlock:^{
				
				if (moreComing)
					[self _fetchRecordChangesWithCompletionHandler:completionHandler];
				else
					dispatch_resume(fetchQueue);
				
				if (completionHandler)
				{
					if (hasChanges)
						completionHandler(UIBackgroundFetchResultNewData, moreComing);
					else
						completionHandler(UIBackgroundFetchResultNoData, moreComing);
				}
			}];
		
		} // end if (hasChanges)
	};
	
	[[[CKContainer defaultContainer] privateCloudDatabase] addOperation:operation];
}

/**
 * This method refetches records that have already been fetched via CKFetchRecordChangesOperation.
 * However, we somehow managed to screw up merging the information into our local CKRecord.
 * This is usually due to bugs in the implementation of your YapDatabaseCloudKitMergeBlock.
 * But bugs are a normal and expected part of development.
 * So rather than fall into an infinite loop,
 * we provide this method as a way to bail ourselves out when we make a mistake.
**/
- (void)_refetchMissedRecordIDs:(NSArray *)recordIDs withCompletionHandler:(void (^)(NSError *error))completionHandler
{
	CKFetchRecordsOperation *operation = [[CKFetchRecordsOperation alloc] initWithRecordIDs:recordIDs];
	
	operation.perRecordCompletionBlock = ^(CKRecord *record, CKRecordID *recordID, NSError *error) {
		
		if (error) {
			DDLogError(@"CKFetchRecordsOperation.perRecordCompletionBlock: %@ -> %@", recordID, error);
		}
	};
	
	operation.fetchRecordsCompletionBlock = ^(NSDictionary *recordsByRecordID, NSError *operationError) {
		
		if (operationError)
		{
			if (completionHandler) {
				completionHandler(operationError);
			}
		}
		else
		{
			DDLogVerbose(@"CKFetchRecordsOperation: recordsByRecordID: %@", recordsByRecordID);
			
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				for (CKRecord *record in [recordsByRecordID objectEnumerator])
				{
					[[transaction ext:Ext_CloudKit] mergeRecord:record databaseIdentifier:nil];
				}
				
			} completionBlock:^{
				
				if (completionHandler) {
					completionHandler(nil);
				}
			}];
		}
	};
	
	[[[CKContainer defaultContainer] privateCloudDatabase] addOperation:operation];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Error Handling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoke me if you get one of the following errors via YapDatabaseCloudKitOperationErrorBlock:
 *
 * - CKErrorNetworkUnavailable
 * - CKErrorNetworkFailure
**/
- (void)handleNetworkError
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	// When the YapDatabaseCloudKitOperationErrorBlock is invoked,
	// the extension has already automatically suspended itself.
	// It is our job to properly handle the error, and resume the extension when ready.
	self.needsResume = YES;
	
	if (MyAppDelegate.reachability.isReachable)
	{
		self.needsResume = NO;
		[MyDatabaseManager.cloudKitExtension resume];
	}
	else
	{
		// Wait for reachability notification
	}
}

/**
 * Invoke me if you get one of the following errors via YapDatabaseCloudKitOperationErrorBlock:
 *
 * - CKErrorPartialFailure
**/
- (void)handlePartialFailure
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	// When the YapDatabaseCloudKitOperationErrorBlock is invoked,
	// the extension has already automatically suspended itself.
	// It is our job to properly handle the error, and resume the extension when ready.
	self.needsResume = YES;
	
	// In the case of a partial failure, we have out-of-date CKRecords.
	// To fix the problem, we need to:
	// - fetch the latest changes from the server
	// - merge these changes with our local/pending CKRecord(s)
	// - retry uploading the CKRecord(s)
	self.needsFetchRecordChanges = YES;
	
	
	YDBCKChangeSet *failedChangeSet = [[MyDatabaseManager.cloudKitExtension pendingChangeSets] firstObject];
	
	if ([failedChangeSet.uuid isEqualToString:lastChangeSetUUID] && self.lastSuccessfulFetchResultWasNoData)
	{
		// We screwed up!
		//
		// Here's what happend:
		// - We fetched all the record changes (via CKFetchRecordChangesOperation).
		// - But we failed to merge the fetched changes into our local CKRecord(s)
		//   because of a bug in your YapDatabaseCloudKitMergeBlock (don't worry, it happens)
		// - So at this point we'd normally fall into an infinite loop:
		//     - We do a CKFetchRecordChangesOperation
		//     - Find there's no new data (since prevServerChangeToken)
		//     - Attempt to upload our modified CKRecord(s)
		//     - Get a partial failure
		//     - We do a CKFetchRecordChangesOperation
		//     - ... infinte loop
		//
		// This is a common problem one might run into during the normal development cycle.
		// As you make changes to your objects & CKRecord format, you may sometimes forget something
		// within the implementation of your YapDatabaseCloudKitMergeBlock. Oops.
		// So we print out a warning here to let you know about the problem.
		
		// And then we refetch the missed records.
		// If you've fixed your YapDatabaseCloudKitMergeBlock,
		// then refetching & re-merging should solve the infinite loop problem.
		
		self.needsRefetchMissedRecordIDs = YES;
		[self _refetchMissedRecordIDs];
	}
	else
	{
		[self _fetchRecordChanges];
	}
}

- (void)_fetchRecordChanges
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	[self fetchRecordChangesWithCompletionHandler:^(UIBackgroundFetchResult result, BOOL moreComing) {
		
		if (result == UIBackgroundFetchResultFailed)
		{
			if (MyAppDelegate.reachability.isReachable)
			{
				[self _fetchRecordChanges]; // try again
			}
			else
			{
				// Wait for reachability notification
			}
		}
		else
		{
			if (!moreComing)
			{
				self.needsFetchRecordChanges = NO;
				
				if (self.needsResume)
				{
					self.needsResume = NO;
					[MyDatabaseManager.cloudKitExtension resume];
				}
			}
		}
	}];
}

- (void)_refetchMissedRecordIDs
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	YDBCKChangeSet *failedChangeSet = [[MyDatabaseManager.cloudKitExtension pendingChangeSets] firstObject];
	NSArray *recordIDs = failedChangeSet.recordIDsToSave;
	
	if (recordIDs.count == 0)
	{
		// Oops, we don't have anything to refetch.
		// Fallback to checking other scenarios.
		
		self.needsRefetchMissedRecordIDs = NO;
		
		if (self.needsFetchRecordChanges)
		{
			[self _fetchRecordChanges];
		}
		else if (self.needsResume)
		{
			self.needsResume = NO;
			[MyDatabaseManager.cloudKitExtension resume];
		}
		
		return;
	}
	
	[self _refetchMissedRecordIDs:recordIDs withCompletionHandler:^(NSError *error) {
		
		if (error)
		{
			if (MyAppDelegate.reachability.isReachable)
			{
				[self _refetchMissedRecordIDs]; // try again
			}
			else
			{
				// Wait for reachability notification
			}
		}
		else
		{
			self.needsRefetchMissedRecordIDs = NO;
			self.needsFetchRecordChanges = NO;
			
			if (self.needsResume)
			{
				self.needsResume = NO;
				[MyDatabaseManager.cloudKitExtension resume];
			}
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	if (self.needsResume == NO)
	{
		self.needsResume = YES;
		[MyDatabaseManager.cloudKitExtension suspend];
	}
	
	self.needsFetchRecordChanges = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	[self _fetchRecordChanges];
}

- (void)cloudKitInFlightChangeSetChanged:(NSNotification *)notification
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	NSString *changeSetUUID = [notification.userInfo objectForKey:@"uuid"];
	
	lastChangeSetUUID = changeSetUUID;
}

- (void)reachabilityChanged:(NSNotification *)notification
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	Reachability *reachability = notification.object;
	
	DDLogInfo(@"%@ - reachability.isReachable = %@", THIS_FILE, (reachability.isReachable ? @"YES" : @"NO"));
	if (reachability.isReachable)
	{
		if (self.needsCreateZone || self.needsCreateZoneSubscription)
		{
			[self configureCloudKit];
		}
		else if (self.needsFetchRecordChangesAfterAppLaunch)
		{
			[self fetchRecordChangesAfterAppLaunch];
		}
		else
		{
			// Order matters here.
			// We may be in one of 3 states:
			//
			// 1. YDBCK is suspended because we need to refetch stuff we screwed up
			// 2. YDBCK is suspended because we need to fetch record changes (and merge with our local CKRecords)
			// 3. YDBCK is suspended because of a network failure
			// 4. YDBCK is not suspended
			//
			// In the case of #1, it doesn't make sense to resume YDBCK until we've refetched the records we
			// didn't properly merge last time (due to a bug in your YapDatabaseCloudKitMergeBlock).
			// So case #3 needs to be checked before #2.
			//
			// In the case of #2, it doesn't make sense to resume YDBCK until we've handled
			// fetching the latest changes from the server.
			// So case #2 needs to be checked before #3.
			
			if (self.needsRefetchMissedRecordIDs)
			{
				[self _refetchMissedRecordIDs];
			}
			else if (self.needsFetchRecordChanges)
			{
				[self _fetchRecordChanges];
			}
			else if (self.needsResume)
			{
				self.needsResume = NO;
				[MyDatabaseManager.cloudKitExtension resume];
			}
		}
	}
}

@end
