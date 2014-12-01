#import "CloudKitManager.h"
#import "DatabaseManager.h"
#import "MyTodo.h"
#import "DDLog.h"

#import <CloudKit/CloudKit.h>

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

- (id)init
{
	NSAssert(MyCloudKitManager == nil, @"Must use sharedInstance singleton (global MyCloudKitManager)");
	
	if ((self = [super init]))
	{
		// We could create our own dedicated databaseConnection.
		// But our needs are pretty basic, so we're just going to use the generic background connection.
		databaseConnection = MyDatabaseManager.bgDatabaseConnection;
		
		[self configureCloudKit];
	}
	return self;
}

- (void)configureCloudKit
{
	__block BOOL needsCreateZone = YES;
	__block BOOL needsCreateZoneSubscription = YES;
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		if ([transaction hasObjectForKey:Key_HasZone inCollection:Collection_CloudKit]) {
			needsCreateZone = NO;
		}
		if ([transaction hasObjectForKey:Key_HasZoneSubscription inCollection:Collection_CloudKit]) {
			needsCreateZoneSubscription = NO;
		}
	}];
	
	void (^ContinueAfterCreateZone)(BOOL updateDatabase) = ^(BOOL updateDatabase){
		
		// Create zone complete.
		// Decrement suspend count.
		[MyDatabaseManager.cloudKitExtension resume];
		
		if (updateDatabase)
		{
			// Put flag in database so we know we can skip this operation next time
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction setObject:@(YES) forKey:Key_HasZone inCollection:Collection_CloudKit];
			}];
		}
	};
	
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
	
	CKModifyRecordZonesOperation *modifyRecordZonesOperation = nil;
	CKModifySubscriptionsOperation *modifySubscriptionsOperation = nil;
	
	// Create CKRecordZone (if needed)
	
	if (needsCreateZone)
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
	
	// Create CKSubscription (if needed)
	
	if (needsCreateZoneSubscription)
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
	[self fetchRecordChangesWithCompletionHandler:^(UIBackgroundFetchResult result, BOOL moreComing) {
		
		if (!moreComing)
		{
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
	__block CKServerChangeToken *serverChangeToken = nil;
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	
		serverChangeToken = [transaction objectForKey:Key_ServerChangeToken inCollection:Collection_CloudKit];
	}];
	
	CKRecordZoneID *recordZoneID =
	  [[CKRecordZoneID alloc] initWithZoneName:CloudKitZoneName ownerName:CKOwnerDefaultName];
	
	CKFetchRecordChangesOperation *operation =
	  [[CKFetchRecordChangesOperation alloc] initWithRecordZoneID:recordZoneID
	                                    previousServerChangeToken:serverChangeToken];
	
	__block NSMutableArray *deletedRecordIDs = nil;
	__block NSMutableArray *changedRecords = nil;
	
	__weak CKFetchRecordChangesOperation *weakOperation = operation;
	
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
	
	operation.fetchRecordChangesCompletionBlock =
	^(CKServerChangeToken *serverChangeToken, NSData *clientChangeTokenData, NSError *operationError){
		
		DDLogVerbose(@"CKFetchRecordChangesOperation.fetchRecordChangesCompletionBlock");
		
		DDLogVerbose(@"CKFetchRecordChangesOperation: serverChangeToken: %@", serverChangeToken);
		DDLogVerbose(@"CKFetchRecordChangesOperation: clientChangeTokenData: %@", clientChangeTokenData);
		
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
		else
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
				[transaction setObject:serverChangeToken
				                forKey:Key_ServerChangeToken
				          inCollection:Collection_CloudKit];
				
			} completionBlock:^{
				
				if (completionHandler)
				{
					if (([deletedRecordIDs count] > 0) || ([changedRecords count] > 0)) {
						completionHandler(UIBackgroundFetchResultNewData, moreComing);
					}
					else {
						completionHandler(UIBackgroundFetchResultNoData, moreComing);
					}
				}
			}];
			
			if (moreComing)
			{
				[self fetchRecordChangesWithCompletionHandler:completionHandler];
			}
		}
	};
	
	[[[CKContainer defaultContainer] privateCloudDatabase] addOperation:operation];
}

@end
