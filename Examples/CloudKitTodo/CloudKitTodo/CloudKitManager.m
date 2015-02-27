#import "CloudKitManager.h"
#import "DatabaseManager.h"
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

@property (atomic, readwrite) BOOL needsCreateZone;
@property (atomic, readwrite) BOOL needsCreateZoneSubscription;
@property (atomic, readwrite) BOOL needsFetchRecordChangesAfterAppLaunch;

@end

@implementation CloudKitManager
{
	YapDatabaseConnection *databaseConnection;
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

@synthesize needsCreateZone;
@synthesize needsCreateZoneSubscription;
@synthesize needsFetchRecordChangesAfterAppLaunch;

- (id)init
{
	NSAssert(MyCloudKitManager == nil, @"Must use sharedInstance singleton (global MyCloudKitManager)");
	
	if ((self = [super init]))
	{
		// We could create our own dedicated databaseConnection.
		// But our needs are pretty basic, so we're just going to use the generic background connection.
		databaseConnection = MyDatabaseManager.bgDatabaseConnection;
		
		self.needsCreateZone = YES;
		self.needsCreateZoneSubscription = YES;
		self.needsFetchRecordChangesAfterAppLaunch = YES;
		
		[self configureCloudKit];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(reachabilityChanged:)
		                                             name:kReachabilityChangedNotification
		                                           object:nil];
	}
	return self;
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
	}
}

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
 * This method is invoked after
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
	__block CKServerChangeToken *prevServerChangeToken = nil;
	
	[databaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		prevServerChangeToken = [transaction objectForKey:Key_ServerChangeToken inCollection:Collection_CloudKit];
		
	} completionBlock:^{
		
		[self fetchRecordChangesWithPrevServerChangeToken:prevServerChangeToken completionHandler:completionHandler];
	}];
}

- (void)fetchRecordChangesWithPrevServerChangeToken:(CKServerChangeToken *)prevServerChangeToken
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
		}
		
		if (operationError)
		{
			// I've seen:
			//
			// - CKErrorNotAuthenticated - "CloudKit access was denied by user settings"; Retry after 3.0 seconds
			
			DDLogError(@"CKFetchRecordChangesOperation: operationError: %@", operationError);
			
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
					
					BOOL exists = [[transaction ext:Ext_CloudKit] containsRecordID:record.recordID
					                                            databaseIdentifier:nil];
					
					if (exists)
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
				
				if (completionHandler)
				{
					if (hasChanges)
						completionHandler(UIBackgroundFetchResultNewData, moreComing);
					else
						completionHandler(UIBackgroundFetchResultNoData, moreComing);
				}
			}];
			
			if (moreComing)
			{
				[self fetchRecordChangesWithCompletionHandler:completionHandler];
			}
		
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
- (void)refetchMissedRecordIDs:(NSArray *)recordIDs withCompletionHandler:(void (^)(NSError *error))completionHandler
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

@end
