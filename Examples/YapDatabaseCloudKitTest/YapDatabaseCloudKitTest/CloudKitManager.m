#import "CloudKitManager.h"
#import "DatabaseManager.h"
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
		
		// Decrement suspend count
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
		
		// Decrement suspend count
		[MyDatabaseManager.cloudKitExtension resume];
		
		if (updateDatabase)
		{
			// Put flag in database so we know we can skip this operation next time
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				[transaction setObject:@(YES) forKey:Key_HasZoneSubscription inCollection:Collection_CloudKit];
			}];
		}
		
		// We're ready to fetch any changes (from other devices)
		[self fetchRecordChangesWithCompletionHandler:NULL];
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
 * This method uses CKFetchRecordChangesOperation to fetch changes.
 * It continues fetching until its reported that we're caught up.
 *
 * This method is invoked once automatically, when the CloudKitManager is initialized.
 * After that, one should invoke it anytime a corresponding push notification is received.
**/
- (void)fetchRecordChangesWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
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
		
		if (operationError)
		{
			completionHandler(UIBackgroundFetchResultFailed);
		}
		else
		{
			BOOL moreComing = weakOperation.moreComing;
			
			[databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
				
				// Remove the stuff that was deleted
				for (CKRecordID *recordID in deletedRecordIDs)
				{
					NSString *key = nil;
					NSString *collection = nil;
					
					BOOL exists = [[transaction ext:Ext_CloudKit] getKey:&key
					                                          collection:&collection
					                                         forRecordID:recordID
					                                  databaseIdentifier:nil];
					
					if (exists) {
						[transaction removeObjectForKey:key inCollection:collection];
					}
				}
				
				// Update the stuff that was changed
				for (CKRecord *record in changedRecords)
				{
					// Todo...
				}
				
				// And save the serverChangeToken. (In the same atomic transaction, FTW!)
				[transaction setObject:serverChangeToken forKey:Key_ServerChangeToken inCollection:Collection_CloudKit];
				
			} completionBlock:^{
				
				if (!moreComing)
				{
					if (([deletedRecordIDs count] > 0) || ([changedRecords count] > 0)) {
						completionHandler(UIBackgroundFetchResultNewData);
					}
					else {
						completionHandler(UIBackgroundFetchResultNoData);
					}
				}
			}];
			
			if (moreComing)
			{
				[self fetchRecordChangesWithCompletionHandler:completionHandler];
			}
		}
	};
}

@end
