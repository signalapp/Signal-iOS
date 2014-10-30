#import "DatabaseManager.h"

#import "MyDatabaseObject.h"
#import "MyTodo.h"

#import "DDLog.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif

DatabaseManager *MyDatabaseManager;

NSString *const Collection_Todos    = @"todos";
NSString *const Collection_CloudKit = @"cloudKit";

NSString *const Ext_View_Order = @"order";
NSString *const Ext_CloudKit   = @"ck";

NSString *const CloudKitZoneName = @"zone1";


@implementation DatabaseManager

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
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseSerializer)dbSerializer
{
	// This is actually the default serializer.
	// We just included it here for completeness.
	
	YapDatabaseSerializer serializer = ^(NSString *collection, NSString *key, id object){
		
		return [NSKeyedArchiver archivedDataWithRootObject:object];
	};
	
	return serializer;
}

- (YapDatabaseDeserializer)dbDeserializer
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

- (YapDatabaseSanitizer)dbSanitizer
{
	YapDatabaseSanitizer sanitizer = ^(NSString *collection, NSString *key, id object){
		
		if ([object isKindOfClass:[MyDatabaseObject class]])
		{
			[(MyDatabaseObject *)object makeImmutable];
		}
		
		return object;
	};
	
	return sanitizer;
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
									  serializer:[self dbSerializer]
									deserializer:[self dbDeserializer]
									   sanitizer:[self dbSanitizer]];
	
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
	uiDatabaseConnection.objectCacheLimit = 400;
	uiDatabaseConnection.metadataCacheEnabled = NO;
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
		
		NSComparisonResult cmp = [todo1.created compare:todo2.created];
		
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
		NSSet *changedProperties = todo.changedProperties;
		if ((changedProperties.count == 0) && (recordInfo.changedKeysToRestore == nil))
		{
			return; // from block
		}
		
		// The YapDatabaseCloudKit extension handles storing the base CKRecord object.
		//
		// That is, a CKRecord object is composed of 2 types of properties:
		// - the internal (system) properties such as the version and other such sync-specific info
		// - the regular key/value properties that we set on the object
		//
		// We configured YapDatabaseCloudKit to store a bare version of the CKRecord,
		// with only the internal (system) properties.
		//
		// So if we've ever handled this collection/key/object before,
		// then YDBCK will hand us a bare CKRecord (with only the internal system info set).
		//
		// Otherwise it will pass a nil CKRecord, and it's our responsibility to create one.
		
		CKRecord *record = inOutRecordPtr ? *inOutRecordPtr : nil;
		
		if (record == nil)
		{
			CKRecordZoneID *zoneID =
			  [[CKRecordZoneID alloc] initWithZoneName:CloudKitZoneName ownerName:CKOwnerDefaultName];
			
			CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:todo.uuid zoneID:zoneID];
			
			record = [[CKRecord alloc] initWithRecordType:@"todo" recordID:recordID];
			*inOutRecordPtr = record;
		}
		
		if (recordInfo.changedKeysToRestore)
		{
			for (NSString *changedPropertyName in recordInfo.changedKeysToRestore)
			{
				id value = [todo valueForKey:changedPropertyName];
				[record setValue:value forKey:changedPropertyName];
			}
		}
		else
		{
			for (NSString *changedPropertyName in changedProperties)
			{
				id value = [todo valueForKey:changedPropertyName];
				[record setValue:value forKey:changedPropertyName];
			}
		}
	}];
	
	YapDatabaseCloudKitMergeBlock mergeBlock =
	^(YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
	  CKRecord *remoteRecord, CKRecord *pendingLocalRecord, CKRecord *newLocalRecord)
	{
		if ([remoteRecord.recordType isEqualToString:@"todo"])
		{
			if (collection == nil)
				collection = Collection_Todos;
			
			if (key == nil)
				key = remoteRecord.recordID.recordName;
			
			MyTodo *todo = [transaction objectForKey:key inCollection:collection];
			
			NSSet *remoteChangedKeys = [NSSet setWithArray:remoteRecord.changedKeys];
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
		}
	};
	
	YapDatabaseCloudKitConflictBlock conflictBlock =
	  ^(YapDatabaseReadWriteTransaction *transaction /* ??? */)
	{
		// Todo...
	};
	
	NSSet *todos = [NSSet setWithObject:Collection_Todos];
	YapWhitelistBlacklist *whitelist = [[YapWhitelistBlacklist alloc] initWithWhitelist:todos];
	
	YapDatabaseCloudKitOptions *options = [[YapDatabaseCloudKitOptions alloc] init];
	options.allowedCollections = whitelist;
	
	cloudKitExtension = [[YapDatabaseCloudKit alloc] initWithRecordHandler:recordHandler
	                                                            mergeBlock:mergeBlock
	                                                         conflictBlock:conflictBlock
	                                                            versionTag:@"1"
	                                                               options:options];
	
	[cloudKitExtension suspend]; // Push registration
	[cloudKitExtension suspend]; // Create zone(s)
	[cloudKitExtension suspend]; // Create subscription(s)
	
	[database asyncRegisterExtension:cloudKitExtension withName:Ext_CloudKit completionBlock:^(BOOL ready) {
		if (!ready) {
			DDLogError(@"Error registering %@ !!!", Ext_CloudKit);
		}
	}];
}

@end
