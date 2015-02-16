#import "DatabaseManager.h"
#import "CloudKitManager.h"
#import "AppDelegate.h"

#import "MyDatabaseObject.h"
#import "MyTodo.h"

#import "DDLog.h"

#import <Reachability/Reachability.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif

NSString *const UIDatabaseConnectionWillUpdateNotification = @"UIDatabaseConnectionWillUpdateNotification";
NSString *const UIDatabaseConnectionDidUpdateNotification  = @"UIDatabaseConnectionDidUpdateNotification";
NSString *const kNotificationsKey = @"notifications";

NSString *const Collection_Todos    = @"todos";
NSString *const Collection_CloudKit = @"cloudKit";

NSString *const Ext_View_Order = @"order";
NSString *const Ext_CloudKit   = @"ck";

NSString *const CloudKitZoneName = @"zone1";

DatabaseManager *MyDatabaseManager;


@implementation DatabaseManager
{
	BOOL cloudKitExtensionNeedsResume;
	BOOL cloudKitExtensionNeedsFetchRecordChanges;
}

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		MyDatabaseManager = [[DatabaseManager alloc] init];
	});
}

+ (instancetype)sharedInstance
{
	return MyDatabaseManager;
}

+ (NSString *)databasePath
{
	NSString *databaseName = @"MyAwesomeApp.sqlite";
	
	NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
	                                                        inDomain:NSUserDomainMask
	                                               appropriateForURL:nil
	                                                          create:YES
	                                                           error:NULL];
	
	NSURL *databaseURL = [baseURL URLByAppendingPathComponent:databaseName isDirectory:NO];
	
	return databaseURL.filePathURL.path;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize database = database;
@synthesize cloudKitExtension = cloudKitExtension;

@synthesize uiDatabaseConnection = uiDatabaseConnection;
@synthesize bgDatabaseConnection = bgDatabaseConnection;

- (id)init
{
	NSAssert(MyDatabaseManager == nil, @"Must use sharedInstance singleton (global MyDatabaseManager)");
	
	if ((self = [super init]))
	{
		[self setupDatabase];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(reachabilityChanged:)
		                                             name:kReachabilityChangedNotification
		                                           object:nil];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseSerializer)databaseSerializer
{
	// This is actually the default serializer.
	// We just included it here for completeness.
	
	YapDatabaseSerializer serializer = ^(NSString *collection, NSString *key, id object){
		
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
	
	return serializer;
}

- (YapDatabaseDeserializer)databaseDeserializer
{
	// Pretty much the default serializer,
	// but it also ensures that objects coming out of the database are immutable.
	
	YapDatabaseDeserializer deserializer = ^(NSString *collection, NSString *key, NSData *data){
		
		id object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		
		if ([object isKindOfClass:[MyDatabaseObject class]])
		{
			[(MyDatabaseObject *)object makeImmutable];
		}
		
		return object;
	};
	
	return deserializer;
}

- (YapDatabasePreSanitizer)databasePreSanitizer
{
	YapDatabasePreSanitizer preSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[MyDatabaseObject class]])
		{
			[(MyDatabaseObject *)object makeImmutable];
		}
		
		return object;
	};
	
	return preSanitizer;
}

- (YapDatabasePostSanitizer)databasePostSanitizer
{
	YapDatabasePostSanitizer postSanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[MyDatabaseObject class]])
		{
			[object clearChangedProperties];
		}
	};
	
	return postSanitizer;
}

- (void)setupDatabase
{
	NSString *databasePath = [[self class] databasePath];
	
	// Configure custom class mappings for NSCoding.
	// In a previous version of the app, the "MyTodo" class was named "MyTodoItem".
	// We renamed the class in a recent version.
	
	[NSKeyedUnarchiver setClass:[MyTodo class] forClassName:@"MyTodoItem"];
	
	// Create the database
	
	database = [[YapDatabase alloc] initWithPath:databasePath
	                                  serializer:[self databaseSerializer]
	                                deserializer:[self databaseDeserializer]
	                                preSanitizer:[self databasePreSanitizer]
	                               postSanitizer:[self databasePostSanitizer]
	                                     options:nil];
	
	// FOR ADVANCED USERS ONLY
	//
	// Do NOT copy this blindly into your app unless you know exactly what you're doing.
	// https://github.com/yapstudios/YapDatabase/wiki/Object-Policy
	//
	database.defaultObjectPolicy = YapDatabasePolicyShare;
	database.defaultMetadataPolicy = YapDatabasePolicyShare;
	//
	// ^^^ FOR ADVANCED USERS ONLY ^^^
	
	// Setup the extensions
	
	[self setupOrderViewExtension];
	[self setupCloudKitExtension];
	
	// Setup database connection(s)
	
	uiDatabaseConnection = [database newConnection];
	uiDatabaseConnection.objectCacheLimit = 400;
	uiDatabaseConnection.metadataCacheEnabled = NO;
	
	#if YapDatabaseEnforcePermittedTransactions
	uiDatabaseConnection.permittedTransactions = YDB_SyncReadTransaction | YDB_MainThreadOnly;
	#endif
	
	bgDatabaseConnection = [database newConnection];
	bgDatabaseConnection.objectCacheLimit = 400;
	bgDatabaseConnection.metadataCacheEnabled = NO;
	
	// Start the longLivedReadTransaction on the UI connection.
	
	[uiDatabaseConnection enableExceptionsForImplicitlyEndingLongLivedReadTransaction];
	[uiDatabaseConnection beginLongLivedReadTransaction];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(yapDatabaseModified:)
	                                             name:YapDatabaseModifiedNotification
	                                           object:database];
}

- (void)setupOrderViewExtension
{
	//
	// What is a YapDatabaseView ?
	//
	// https://github.com/yapstudios/YapDatabase/wiki/Views
	//
	// > If you're familiar with Core Data, it's kinda like a NSFetchedResultsController.
	// > But you should really read that wiki article, or you're likely to be a bit confused.
	//
	//
	// This view keeps a persistent "list" of MyTodo items sorted by timestamp.
	// We use it to drive the tableView.
	//
	
	YapDatabaseViewGrouping *orderGrouping = [YapDatabaseViewGrouping withObjectBlock:
	    ^NSString *(NSString *collection, NSString *key, id object)
	{
		if ([object isKindOfClass:[MyTodo class]])
		{
			return @""; // include in view
		}
		
		return nil; // exclude from view
	}];
	
	YapDatabaseViewSorting *orderSorting = [YapDatabaseViewSorting withObjectBlock:
	    ^(NSString *group, NSString *collection1, NSString *key1, MyTodo *todo1,
	                       NSString *collection2, NSString *key2, MyTodo *todo2)
	{
		// We want:
		// - Most recently created Todo at index 0.
		// - Least recent created Todo at the end.
		//
		// This is descending order (opposite of "standard" in Cocoa) so we swap the normal comparison.
		
		NSComparisonResult cmp = [todo1.creationDate compare:todo2.creationDate];
		
		if (cmp == NSOrderedAscending) return NSOrderedDescending;
		if (cmp == NSOrderedDescending) return NSOrderedAscending;
		
		return NSOrderedSame;
	}];
	
	YapDatabaseView *orderView =
	  [[YapDatabaseView alloc] initWithGrouping:orderGrouping
	                                    sorting:orderSorting
	                                 versionTag:@"sortedByCreationDate"];
	
	[database asyncRegisterExtension:orderView withName:Ext_View_Order completionBlock:^(BOOL ready) {
		if (!ready) {
			DDLogError(@"Error registering %@ !!!", Ext_View_Order);
		}
	}];
}

- (void)setupCloudKitExtension
{
	YapDatabaseCloudKitRecordHandler *recordHandler = [YapDatabaseCloudKitRecordHandler withObjectBlock:
	    ^(CKRecord *__autoreleasing *inOutRecordPtr, YDBCKRecordInfo *recordInfo,
		  NSString *collection, NSString *key, MyTodo *todo)
	{
		CKRecord *record = inOutRecordPtr ? *inOutRecordPtr : nil;
		if (record &&                                    // not a newly inserted object
		    (todo.hasChangedSyncableProperties == NO) && // no sync'd properties changed in the todo
		    (recordInfo.changedKeysToRestore == nil))    // and we don't need to restore "truth" values
		{
			// Thus we don't have any changes we need to push to the cloud
			return;
		}
		
		// The CKRecord will be nil when we first insert an object into the database.
		// Or if we've never included this item for syncing before.
		//
		// Otherwise we'll be handed a bare CKRecord, with only the proper CKRecordID
		// and the sync metadata set.
		
		BOOL isNewRecord = NO;
		
		if (record == nil)
		{
			CKRecordZoneID *zoneID =
			  [[CKRecordZoneID alloc] initWithZoneName:CloudKitZoneName ownerName:CKOwnerDefaultName];
			
			CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:todo.uuid zoneID:zoneID];
			
			record = [[CKRecord alloc] initWithRecordType:@"todo" recordID:recordID];
			
			*inOutRecordPtr = record;
			isNewRecord = YES;
		}
		
		id <NSFastEnumeration> properties = nil;
		
		if (recordInfo.changedKeysToRestore)
		{
			// We need to restore "truth" values for YapDatabaseCloudKit.
			// This happens when the extension is restarted,
			// and it needs to restore its change-set queue (to pick up where it left off).
			
			properties = recordInfo.changedKeysToRestore;
		}
		else if (isNewRecord)
		{
			// This is a CKRecord for a newly inserted todo item.
			// So we want to get every single property,
			// including those that are read-only, and may have been set directly via the init method.
			
			properties = todo.allSyncableProperties;
		}
		else
		{
			// We changed one or more properties of our Todo item.
			// So we need to copy only these changed values into the CKRecord.
			// That way YapDatabaseCloudKit can handle syncing it to the cloud.
			
			properties = todo.changedSyncableProperties;
		}
		
		for (NSString *propertyName in properties)
		{
			id value = [todo valueForKey:propertyName];
			[record setValue:value forKey:propertyName];
		}
	}];
	
	YapDatabaseCloudKitMergeBlock mergeBlock =
	^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
	  CKRecord *remoteRecord, CKRecord *pendingLocalRecord, CKRecord *newLocalRecord)
	{
		if ([remoteRecord.recordType isEqualToString:@"todo"])
		{
			MyTodo *todo = [transaction objectForKey:key inCollection:collection];
			todo = [todo copy]; // make mutable copy
			
			NSSet *remoteChangedKeys = nil;
			if (remoteRecord.changedKeys.count > 0)
				remoteChangedKeys = [NSSet setWithArray:remoteRecord.changedKeys];
			else
				remoteChangedKeys = [NSSet setWithArray:remoteRecord.allKeys];
			
			NSMutableSet *localChangedKeys = [NSMutableSet setWithArray:pendingLocalRecord.changedKeys];
			
			for (NSString *remoteChangedKey in remoteChangedKeys)
			{
				id remoteChangedValue = [remoteRecord valueForKey:remoteChangedKey];
				
				[todo setValue:remoteChangedValue forKey:remoteChangedKey];
				[localChangedKeys removeObject:remoteChangedKey];
			}
			for (NSString *localChangedKey in localChangedKeys)
			{
				id localChangedValue = [pendingLocalRecord valueForKey:localChangedKey];
				[newLocalRecord setValue:localChangedValue forKey:localChangedKey];
			}
			
			[transaction setObject:todo forKey:key inCollection:collection];
		}
	};
	
	__weak typeof(self) weakSelf = self;
	
	YapDatabaseCloudKitOperationErrorBlock opErrorBlock =
	  ^(NSString *databaseIdentifier, NSError *operationError)
	{
		NSInteger ckErrorCode = operationError.code;
		
		if (ckErrorCode == CKErrorPartialFailure)
		{
			[weakSelf cloudKit_handlePartialFailure];
		}
		else if (ckErrorCode == CKErrorNetworkUnavailable ||
		         ckErrorCode == CKErrorNetworkFailure)
		{
			[weakSelf cloudKit_handleNetworkError];
		}
		else
		{
			// You'll want to add more error handling here.
			
			DDLogError(@"Unhandled ckErrorCode: %ld", (long)ckErrorCode);
		}
	};
	
	NSSet *todos = [NSSet setWithObject:Collection_Todos];
	YapWhitelistBlacklist *whitelist = [[YapWhitelistBlacklist alloc] initWithWhitelist:todos];
	
	YapDatabaseCloudKitOptions *options = [[YapDatabaseCloudKitOptions alloc] init];
	options.allowedCollections = whitelist;
	
	cloudKitExtension = [[YapDatabaseCloudKit alloc] initWithRecordHandler:recordHandler
	                                                            mergeBlock:mergeBlock
	                                                   operationErrorBlock:opErrorBlock
	                                                            versionTag:@"1"
	                                                           versionInfo:nil
	                                                               options:options];
	
	[cloudKitExtension suspend]; // Create zone(s)
	[cloudKitExtension suspend]; // Create zone subscription(s)
	[cloudKitExtension suspend]; // Initial fetchRecordChanges operation
	
	[database asyncRegisterExtension:cloudKitExtension withName:Ext_CloudKit completionBlock:^(BOOL ready) {
		if (!ready) {
			DDLogError(@"Error registering %@ !!!", Ext_CloudKit);
		}
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark CloudKit Error Handling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)cloudKit_handlePartialFailure
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	[MyCloudKitManager fetchRecordChangesWithCompletionHandler:^(UIBackgroundFetchResult result, BOOL moreComing) {
		
		if (result == UIBackgroundFetchResultFailed)
		{
			if (MyAppDelegate.reachability.isReachable) {
				[self cloudKit_handlePartialFailure]; // try again
			}
			else {
				cloudKitExtensionNeedsFetchRecordChanges = YES;
			}
		}
		else if (!moreComing)
		{
			cloudKitExtensionNeedsResume = NO;
			cloudKitExtensionNeedsFetchRecordChanges = NO;
			
			[cloudKitExtension resume];
		}
	}];
}

- (void)cloudKit_handleNetworkError
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	if (MyAppDelegate.reachability.isReachable)
	{
		[cloudKitExtension resume];
	}
	else
	{
		// Wait for notification
		cloudKitExtensionNeedsResume = YES;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)yapDatabaseModified:(NSNotification *)ignored
{
	// Notify observers we're about to update the database connection
	
	[[NSNotificationCenter defaultCenter] postNotificationName:UIDatabaseConnectionWillUpdateNotification
	                                                    object:self];
	
	// Move uiDatabaseConnection to the latest commit.
	// Do so atomically, and fetch all the notifications for each commit we jump.
	
	NSArray *notifications = [uiDatabaseConnection beginLongLivedReadTransaction];
	
	// Notify observers that the uiDatabaseConnection was updated
	
	NSDictionary *userInfo = @{
	  kNotificationsKey : notifications,
	};

	[[NSNotificationCenter defaultCenter] postNotificationName:UIDatabaseConnectionDidUpdateNotification
	                                                    object:self
	                                                  userInfo:userInfo];
}

- (void)reachabilityChanged:(NSNotification *)notification
{
	DDLogInfo(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	Reachability *reachability = notification.object;
	
	DDLogInfo(@"%@ - reachability.isReachable = %@", THIS_FILE, (reachability.isReachable ? @"YES" : @"NO"));
	if (reachability.isReachable)
	{
		if (cloudKitExtensionNeedsResume)
		{
			cloudKitExtensionNeedsResume = NO;
			[cloudKitExtension resume];
		}
		else if (cloudKitExtensionNeedsFetchRecordChanges)
		{
			[self cloudKit_handlePartialFailure];
		}
	}
}

@end
