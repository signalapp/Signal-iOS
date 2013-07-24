#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"

#import <objc/runtime.h>
#import <libkern/OSAtomic.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif

#define DEFAULT_OBJECT_CACHE_LIMIT   250
#define DEFAULT_METADATA_CACHE_LIMIT 500


@implementation YapAbstractDatabaseConnection {

	OSSpinLock lock;
	BOOL writeQueueSuspended;
	BOOL activeReadWriteTransaction;
	
/* As declared in YapAbstractDatabasePrivate.h :

@private
	sqlite3_stmt *beginTransactionStatement;
	sqlite3_stmt *commitTransactionStatement;
	
	sqlite3_stmt *yapGetDataForKeyStatement; // Against "yap2" database, for internal use
	sqlite3_stmt *yapSetDataForKeyStatement; // Against "yap2" database, for internal use
	
	NSDictionary *registeredExtensions;
	NSMutableDictionary *extensions;
	BOOL extensionsReady;
 
@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
@public
	sqlite3 *db;
	
	BOOL rollback
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL needsMarkSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.

*/
}

+ (void)load
{
	static BOOL loaded = NO;
	if (!loaded)
	{
		// Method swizzle:
		// Both extension: and ext: are designed to be the same method (with ext: shorthand for extension:).
		// So swap out the ext: method to point to extension:.
		
		Method extMethod = class_getInstanceMethod([self class], @selector(ext:));
		IMP extensionIMP = class_getMethodImplementation([self class], @selector(extension:));
		
		method_setImplementation(extMethod, extensionIMP);
		loaded = YES;
	}
}

- (id)initWithDatabase:(YapAbstractDatabase *)inDatabase
{
	if ((self = [super init]))
	{
		database = inDatabase;
		connectionQueue = dispatch_queue_create("YapDatabaseConnection", NULL);
		
		IsOnConnectionQueueKey = &IsOnConnectionQueueKey;
		dispatch_queue_set_specific(connectionQueue, IsOnConnectionQueueKey, IsOnConnectionQueueKey, NULL);
		
		pendingChangesets = [[NSMutableArray alloc] init];
		processedChangesets = [[NSMutableArray alloc] init];
		
		extensions = [[NSMutableDictionary alloc] init];
		
		objectCacheLimit = DEFAULT_OBJECT_CACHE_LIMIT;
		objectCache = [[YapCache alloc] initWithKeyClass:[database cacheKeyClass]];
		objectCache.countLimit = objectCacheLimit;
		
		metadataCacheLimit = DEFAULT_METADATA_CACHE_LIMIT;
		metadataCache = [[YapCache alloc] initWithKeyClass:[database cacheKeyClass]];
		metadataCache.countLimit = metadataCacheLimit;
		
		#if TARGET_OS_IPHONE
		self.autoFlushMemoryLevel = YapDatabaseConnectionFlushMemoryLevelMild;
		#endif
		
		lock = OS_SPINLOCK_INIT;
		
		// Open the database connection.
		//
		// We use SQLITE_OPEN_NOMUTEX to use the multi-thread threading mode,
		// as we will be serializing access to the connection externally.
		
		int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX;
		
		int status = sqlite3_open_v2([database.databasePath UTF8String], &db, flags, NULL);
		if (status != SQLITE_OK)
		{
			// Sometimes the open function returns a db to allow us to query it for the error message
			if (db) {
				YDBLogWarn(@"Error opening database: %d %s", status, sqlite3_errmsg(db));
			}
			else {
				YDBLogError(@"Error opening database: %d", status);
			}
		}
		else
		{
			// Disable autocheckpointing.
			//
			// YapDatabase has its own optimized checkpointing algorithm built-in.
			// It knows the state of every active connection for the database,
			// so it can invoke the checkpoint methods at the precise time in which a checkpoint can be most effective.
			
			sqlite3_wal_autocheckpoint(db, 0);
		}
		
		#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(didReceiveMemoryWarning:)
		                                             name:UIApplicationDidReceiveMemoryWarningNotification
		                                           object:nil];
		#endif
	}
	return self;
}

/**
 * This method will be invoked before any other method.
 * It can be used to do any setup that may be needed.
**/
- (void)prepare
{
	// This method is invoked from our connectionQueue, within the snapshotQueue.
	// Don't do anything expensive here that might tie up the snapshotQueue.
	
	snapshot = [database snapshot];
	registeredExtensions = [database registeredExtensions];
	
	extensionsReady = ([registeredExtensions count] == 0);
}

- (void)dealloc
{
	YDBLogVerbose(@"Dealloc <YapDatabaseConnection %p: databaseName=%@>",
				  self, [database.databasePath lastPathComponent]);
	
	dispatch_sync(connectionQueue, ^{ @autoreleasepool {
		
		if (longLivedReadTransaction) {
			[self postReadTransaction:longLivedReadTransaction];
			longLivedReadTransaction = nil;
		}
	}});
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	sqlite_finalize_null(&yapGetDataForKeyStatement);
	sqlite_finalize_null(&yapSetDataForKeyStatement);
	sqlite_finalize_null(&yapRemoveExtensionStatement);
	sqlite_finalize_null(&rollbackTransactionStatement);
	sqlite_finalize_null(&beginTransactionStatement);
	sqlite_finalize_null(&commitTransactionStatement);
	
	if (db)
		sqlite3_close(db);
	
	[database removeConnection:self];
	
#if !OS_OBJECT_USE_OBJC
	if (connectionQueue)
		dispatch_release(connectionQueue);
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize abstractDatabase = database;
@synthesize connectionQueue = connectionQueue;

#if TARGET_OS_IPHONE
@synthesize autoFlushMemoryLevel;
#endif

- (BOOL)objectCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{
		result = (objectCache != nil);
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

- (void)setObjectCacheEnabled:(BOOL)flag
{
	dispatch_block_t block = ^{
		
		if (flag) // Enabled
		{
			if (objectCache == nil)
			{
				objectCache = [[YapCache alloc] initWithKeyClass:[database cacheKeyClass]];
				objectCache.countLimit = objectCacheLimit;
			}
		}
		else // Disabled
		{
			objectCache = nil;
		}
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(connectionQueue, block);
}

- (NSUInteger)objectCacheLimit
{
	__block NSUInteger result = 0;
	
	dispatch_block_t block = ^{
		result = objectCacheLimit;
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

- (void)setObjectCacheLimit:(NSUInteger)newObjectCacheLimit
{
	dispatch_block_t block = ^{
		
		if (objectCacheLimit != newObjectCacheLimit)
		{
			objectCacheLimit = newObjectCacheLimit;
			
			if (objectCache == nil)
			{
				return; // Limit changed, but objectCache is still disabled
			}
			else
			{
				objectCache.countLimit = objectCacheLimit;
			}
		}
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(connectionQueue, block);
}

- (BOOL)metadataCacheEnabled
{
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{
		result = (metadataCache != nil);
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

- (void)setMetadataCacheEnabled:(BOOL)flag
{
	dispatch_block_t block = ^{
		
		if (flag) // Enabled
		{
			if (metadataCache == nil)
			{
				metadataCache = [[YapCache alloc] initWithKeyClass:[database cacheKeyClass]];
				metadataCache.countLimit = metadataCacheLimit;
			}
		}
		else // Disabled
		{
			metadataCache = nil;
		}
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(connectionQueue, block);
}

- (NSUInteger)metadataCacheLimit
{
	__block NSUInteger result = 0;
	
	dispatch_block_t block = ^{
		result = metadataCacheLimit;
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

- (void)setMetadataCacheLimit:(NSUInteger)newMetadataCacheLimit
{
	dispatch_block_t block = ^{
		
		if (metadataCacheLimit != newMetadataCacheLimit)
		{
			metadataCacheLimit = newMetadataCacheLimit;
			
			if (metadataCache == nil)
			{
				return; // Limit changed but metadataCache still disabled
			}
			else
			{
				metadataCache.countLimit = metadataCacheLimit;
			}
		}
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_async(connectionQueue, block);
}

- (uint64_t)snapshot
{
	__block uint64_t result = 0;
	
	dispatch_block_t block = ^{
		result = snapshot;
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Long-Lived Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)beginLongLivedReadTransaction
{
	__block NSMutableArray *notifications = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		if (longLivedReadTransaction)
		{
			// Caller using implicit atomic reBeginLongLivedReadTransaction
			notifications = (NSMutableArray *)[self endLongLivedReadTransaction];
		}
		
		longLivedReadTransaction = [self newReadTransaction];
		[self preReadTransaction:longLivedReadTransaction];
		
		// The preReadTransaction method acquires the "sqlite-level" snapshot.
		// In doing so, if it needs to fetch and process any changesets,
		// then it adds them to the processedChangesets ivar for us.
		
		if (notifications == nil)
			notifications = [NSMutableArray arrayWithCapacity:[processedChangesets count]];
		
		for (NSDictionary *changeset in processedChangesets)
		{
			// The changeset has already been processed.
			
			NSNotification *notification = [changeset objectForKey:@"notification"];
			if (notification) {
				[notifications addObject:notification];
			}
		}
		
		[processedChangesets removeAllObjects];
	}};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return notifications;
}

- (NSArray *)endLongLivedReadTransaction
{
	__block NSMutableArray *notifications = nil;
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		if (longLivedReadTransaction)
		{
			// End the transaction (sqlite commit)
			
			[self postReadTransaction:longLivedReadTransaction];
			longLivedReadTransaction = nil;
			
			// Now process any changesets that were pending.
			// And extract the corresponding external notifications to return the the caller.
			
			notifications = [NSMutableArray arrayWithCapacity:[pendingChangesets count]];
			
			for (NSDictionary *changeset in pendingChangesets)
			{
				[self noteCommittedChanges:changeset];
				
				NSNotification *notification = [changeset objectForKey:@"notification"];
				if (notification) {
					[notifications addObject:notification];
				}
			}
			
			[pendingChangesets removeAllObjects];
		}
	}};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return notifications;
}

- (BOOL)isInLongLivedReadTransaction
{
	__block BOOL result = NO;
	
	dispatch_block_t block = ^{
		
		result = (longLivedReadTransaction != nil);
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates or fetches the extension with the given name.
 * If this connection has not yet initialized the proper extensions connection, it is done automatically.
 *
 * @return
 *     A subclass of YapAbstractDatabaseExtensionConnection,
 *     according to the type of extension registered under the given name.
 *
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 *
 * @see [YapAbstractDatabase registerExtension:withName:]
**/
- (id)extension:(NSString *)extName
{
	// This method is PUBLIC.
	//
	// This method returns a subclass of YapAbstractDatabaseExtensionConnection.
	// To get:
	// - YapAbstractDatabaseExtension            => [database registeredExtension:@"registeredNameOfExtension"]
	// - YapAbstractDatabaseExtensionConnection  => [databaseConnection extension:@"registeredNameOfExtension"]
	// - YapAbstractDatabaseExtensionTransaction => [databaseTransaction extension:@"registeredNameOfExtension"]
	
	__block id extConnection = nil;
	
	dispatch_block_t block = ^{
		
		extConnection = [extensions objectForKey:extName];
		
		if (!extConnection && !extensionsReady)
		{
			// We don't have an existing connection for the extension.
			// Create one (if we can).
			
			YapAbstractDatabaseExtension *ext = [registeredExtensions objectForKey:extName];
			if (ext)
			{
				extConnection = [ext newConnection:self];
				[extensions setObject:extConnection forKey:extName];
			}
		}
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
	
	return extConnection;
}

- (id)ext:(NSString *)extensionName
{
	// The "+ (void)load" method swizzles the implementation of this class
	// to point to the implementation of the extension: method.
	//
	// So the two methods are literally the same thing.
	
	return [self extension:extensionName]; // This method is swizzled !
}

- (NSDictionary *)extensions
{
	// This method is INTERNAL
	
	if (!extensionsReady)
	{
		[registeredExtensions enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			
			__unsafe_unretained NSString *extName = key;
			__unsafe_unretained YapAbstractDatabaseExtension *ext = obj;
			
			if ([extensions objectForKey:extName] == nil)
			{
				id extConnection = [ext newConnection:self];
				[extensions setObject:extConnection forKey:extName];
			}
		}];
		
		extensionsReady = YES;
	}
	
	return extensions;
}

- (BOOL)registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName
{
	NSAssert(dispatch_get_specific(database->IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	__block BOOL result = NO;
	
	dispatch_sync(connectionQueue, ^{ @autoreleasepool {
	
		YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
		[self preReadWriteTransaction:transaction];
		
		YapAbstractDatabaseExtensionConnection *extensionConnection;
		YapAbstractDatabaseExtensionTransaction *extensionTransaction;
		
		extensionConnection = [extension newConnection:self];
		extensionTransaction = [extensionConnection newReadWriteTransaction:transaction];
		
		BOOL isFirstTimeRegistration = NO;
		[self willRegisterExtension:extension
		            withTransaction:transaction
		    isFirstTimeRegistration:&isFirstTimeRegistration];
		
		result = [extensionTransaction createIfNeeded];
		
		if (result)
		{
			[self didRegisterExtension:extension
			           withTransaction:transaction
			   isFirstTimeRegistration:isFirstTimeRegistration];
			
			[self addRegisteredExtensionConnection:extensionConnection];
			[transaction addRegisteredExtensionTransaction:extensionTransaction];
		}
		else
		{
			[transaction rollback];
		}
		
		[self postReadWriteTransaction:transaction];
		registeredExtensionsChanged = NO;
	}});
	
	return result;
}

- (void)unregisterExtension:(NSString *)extensionName
{
	NSAssert(dispatch_get_specific(database->IsOnWriteQueueKey), @"Must go through writeQueue.");
	
	dispatch_sync(connectionQueue, ^{ @autoreleasepool {
		
		YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
		[self preReadWriteTransaction:transaction];
		
		NSString *className = [transaction stringValueForKey:@"class" extension:extensionName];
		Class class = NSClassFromString(className);
		
		if (className == nil)
		{
			YDBLogWarn(@"Unable to unregister extension(%@). Doesn't appear to be registered.", extensionName);
		}
		else if (class == NULL)
		{
			YDBLogError(@"Unable to unregister extension(%@) with unknown class(%@)", extensionName, className);
		}
		if (![class isSubclassOfClass:[YapAbstractDatabaseExtension class]])
		{
			YDBLogError(@"Unable to unregister extension(%@) with improper class(%@)", extensionName, className);
		}
		else
		{
			// Drop tables
			[class dropTablesForRegisteredName:extensionName withTransaction:transaction];
			
			// Drop preferences (rows in yap2 table)
			[transaction removeAllValuesForExtension:extensionName];
			
			[self didUnregisterExtension:extensionName];
			
			[self removeRegisteredExtensionConnection:extensionName];
			[transaction removeRegisteredExtensionTransaction:extensionName];
		}
		
		[self postReadWriteTransaction:transaction];
		registeredExtensionsChanged = NO;
	}});
}

- (void)willRegisterExtension:(YapAbstractDatabaseExtension *)extension
              withTransaction:(YapAbstractDatabaseTransaction *)transaction
      isFirstTimeRegistration:(BOOL *)isFirstTimeRegistrationPtr
{
	// This method is INTERNAL
	//
	// The class name of every registered extension is recorded in the yap2 table.
	// We ensure that re-registrations under the same name use the same extension class.
	// If we detect a change, we auto-unregister the previous extension.
	//
	// Note: @"class" is a reserved key for all extensions.
	
	NSString *extensionName = extension.registeredName;
	
	NSString *prevExtensionClassName = [transaction stringValueForKey:@"class" extension:extensionName];
	if (prevExtensionClassName == nil)
	{
		*isFirstTimeRegistrationPtr = YES;
		return;
	}
	
	NSString *extensionClassName = NSStringFromClass([extension class]);
	
	if ([prevExtensionClassName isEqualToString:extensionClassName])
	{
		*isFirstTimeRegistrationPtr = NO;
		return;
	}
	
	YDBLogWarn(@"Dropping tables for previously registered extension with name(%@), class(%@) for new class(%@)",
	           extensionName, prevExtensionClassName, extensionClassName);
	
	Class prevExtensionClass = NSClassFromString(prevExtensionClassName);
	
	if (prevExtensionClass == NULL)
	{
		YDBLogError(@"Unable to drop tables for previously registered extension with name(%@), unknown class(%@)",
		            extensionName, prevExtensionClassName);
	}
	else if (![prevExtensionClass isSubclassOfClass:[YapAbstractDatabaseExtension class]])
	{
		YDBLogError(@"Unable to drop tables for previously registered extension with name(%@), invalid class(%@)",
		            extensionName, prevExtensionClassName);
	}
	else
	{
		[prevExtensionClass dropTablesForRegisteredName:extensionName withTransaction:transaction];
	}
	
	*isFirstTimeRegistrationPtr = YES;
}

- (void)didRegisterExtension:(YapAbstractDatabaseExtension *)extension
             withTransaction:(YapAbstractDatabaseTransaction *)transaction
     isFirstTimeRegistration:(BOOL)isFirstTimeRegistration
{
	// This method is INTERNAL
	
	NSString *extensionName = extension.registeredName;
	
	// Record the class name of the extension in the yap2 table.
	
	if (isFirstTimeRegistration)
	{
		NSString *extensionClassName = NSStringFromClass([extension class]);
		
		[transaction setStringValue:extensionClassName forKey:@"class" extension:extensionName];
	}
	
	// Update the list of registered extensions.
	
	NSMutableDictionary *newRegisteredExtensions = [registeredExtensions mutableCopy];
	[newRegisteredExtensions setObject:extension forKey:extensionName];
	
	registeredExtensions = [newRegisteredExtensions copy];
	extensionsReady = NO;
	
	// Set the registeredExtensionsChanged flag.
	// This will be consulted during the creation of the changeset,
	// and will cause us to add the updated registeredExtensions to the list of changes.
	// It will then get propogated to the database, and all other connections.
	
	registeredExtensionsChanged = YES;
}

- (void)didUnregisterExtension:(NSString *)extensionName
{
	// This method is INTERNAL
	
	if ([registeredExtensions objectForKey:extensionName])
	{
		NSMutableDictionary *newRegisteredExtensions = [registeredExtensions mutableCopy];
		[newRegisteredExtensions removeObjectForKey:extensionName];
		
		registeredExtensions = [newRegisteredExtensions copy];
		extensionsReady = NO;
		
		// Set the registeredExtensionsChanged flag.
		// This will be consulted during the creation of the changeset,
		// and will cause us to add the updated registeredExtensions to the list of changes.
		// It will then get propogated to the database, and all other connections.
		
		registeredExtensionsChanged = YES;
	}
}

- (void)addRegisteredExtensionConnection:(YapAbstractDatabaseExtensionConnection *)extConnection
{
	// This method is INTERNAL
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	NSString *extName = [[extConnection extension] registeredName];
	
	[extensions setObject:extConnection forKey:extName];
}

- (void)removeRegisteredExtensionConnection:(NSString *)extName
{
	// This method is INTERNAL
	
	[extensions removeObjectForKey:extName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Memory
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Optional override hook.
 * Don't forget to invoke [super _flushMemoryWithLevel:level].
**/
- (void)_flushMemoryWithLevel:(int)level
{
	if (level >= YapDatabaseConnectionFlushMemoryLevelMild)
	{
		[objectCache removeAllObjects];
		[metadataCache removeAllObjects];
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelModerate)
	{
		sqlite_finalize_null(&yapRemoveExtensionStatement);
		sqlite_finalize_null(&rollbackTransactionStatement);
	}
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
		sqlite_finalize_null(&yapGetDataForKeyStatement);
		sqlite_finalize_null(&yapSetDataForKeyStatement);
		sqlite_finalize_null(&beginTransactionStatement);
		sqlite_finalize_null(&commitTransactionStatement);
	}
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extConnectionObj, BOOL *stop) {
		
		[(YapAbstractDatabaseExtensionConnection *)extConnectionObj _flushMemoryWithLevel:level];
	}];
}

/**
 * This method may be used to flush the internal caches used by the connection,
 * as well as flushing pre-compiled sqlite statements.
 * Depending upon how often you use the database connection,
 * you may want to be more or less aggressive on how much stuff you flush.
 *
 * YapDatabaseConnectionFlushMemoryLevelNone (0):
 *     No-op. Doesn't flush any caches or anything from internal memory.
 *
 * YapDatabaseConnectionFlushMemoryLevelMild (1):
 *     Flushes the object cache and metadata cache.
 *
 * YapDatabaseConnectionFlushMemoryLevelModerate (2):
 *     Mild plus drops less common pre-compiled sqlite statements.
 *
 * YapDatabaseConnectionFlushMemoryLevelFull (3):
 *     Full flush of all caches and removes all pre-compiled sqlite statements.
**/
- (void)flushMemoryWithLevel:(int)level
{
	dispatch_block_t block = ^{
		
		// Invoke internal method to allow for override hook(s)
		[self _flushMemoryWithLevel:level];
	};
	
	if (dispatch_get_specific(IsOnConnectionQueueKey))
		block();
	else
		dispatch_sync(connectionQueue, block);
}

#if TARGET_OS_IPHONE
- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
	[self flushMemoryWithLevel:[self autoFlushMemoryLevel]];
}
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)beginTransactionStatement
{
	if (beginTransactionStatement == NULL)
	{
		char *stmt = "BEGIN TRANSACTION;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &beginTransactionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return beginTransactionStatement;
}

- (sqlite3_stmt *)commitTransactionStatement
{
	if (commitTransactionStatement == NULL)
	{
		char *stmt = "COMMIT TRANSACTION;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &commitTransactionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return commitTransactionStatement;
}

- (sqlite3_stmt *)rollbackTransactionStatement
{
	if (rollbackTransactionStatement == NULL)
	{
		char *stmt = "ROLLBACK TRANSACTION;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &rollbackTransactionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return rollbackTransactionStatement;
}

- (sqlite3_stmt *)yapGetDataForKeyStatement
{
	if (yapGetDataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\" FROM \"yap2\" WHERE \"extension\" = ? AND \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &yapGetDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return yapGetDataForKeyStatement;
}

- (sqlite3_stmt *)yapSetDataForKeyStatement
{
	if (yapSetDataForKeyStatement == NULL)
	{
		char *stmt = "INSERT OR REPLACE INTO \"yap2\" (\"extension\", \"key\", \"data\") VALUES (?, ?, ?);";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &yapSetDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return yapSetDataForKeyStatement;
}

- (sqlite3_stmt *)yapRemoveExtensionStatement
{
	if (yapRemoveExtensionStatement)
	{
		char *stmt = "DELETE FROM \"yap2\" WHERE \"extension\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, (int)strlen(stmt)+1, &yapRemoveExtensionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating '%@': %d %s", NSStringFromSelector(_cmd), status, sqlite3_errmsg(db));
		}
	}
	
	return yapRemoveExtensionStatement;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Access
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Read-only access to the database.
 * 
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * The only time this method ever blocks is if another thread is currently using this connection instance
 * to execute a readBlock or readWriteBlock. Recall that you may create multiple connections for concurrent access.
 *
 * This method is synchronous.
**/
- (void)_readWithBlock:(void (^)(id))block
{
	dispatch_sync(connectionQueue, ^{ @autoreleasepool {
		
		if (longLivedReadTransaction)
		{
			block(longLivedReadTransaction);
		}
		else
		{
			YapAbstractDatabaseTransaction *transaction = [self newReadTransaction];
		
			[self preReadTransaction:transaction];
			block(transaction);
			[self postReadTransaction:transaction];
		}
	}});
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus this method may block if another sibling connection is currently executing a read-write block.
 *
 * This method is synchronous.
**/
- (void)_readWriteWithBlock:(void (^)(id))block
{
	// Order matters.
	// First go through the serial connection queue.
	// Then go through serial write queue for the database.
	//
	// Once we're inside the database writeQueue, we know that we are the only write transaction.
	// No other transaction can possibly modify the database except us, even in other connections.
	
	dispatch_sync(connectionQueue, ^{
		
		if (longLivedReadTransaction)
		{
			YDBLogWarn(@"Implicitly ending long-lived read transaction on connection %@, database %@",
			           self, self->database);
			
			[self endLongLivedReadTransaction];
		}
		
		__preWriteQueue(self);
		dispatch_sync(database->writeQueue, ^{ @autoreleasepool {
			
			YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
			
			[self preReadWriteTransaction:transaction];
			block(transaction);
			[self postReadWriteTransaction:transaction];
			
		}}); // End dispatch_sync(database->writeQueue)
		__postWriteQueue(self);
	});      // End dispatch_sync(connectionQueue)
}

/**
 * Read-only access to the database.
 *
 * The given block can run concurrently with sibling connections,
 * regardless of whether the sibling connections are executing read-only or read-write transactions.
 *
 * This method is asynchronous.
**/
- (void)_asyncReadWithBlock:(void (^)(id))block
            completionBlock:(dispatch_block_t)completionBlock
            completionQueue:(dispatch_queue_t)completionQueue
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	dispatch_async(connectionQueue, ^{ @autoreleasepool {
		
		if (longLivedReadTransaction)
		{
			block(longLivedReadTransaction);
		}
		else
		{
			YapAbstractDatabaseTransaction *transaction = [self newReadTransaction];
			
			[self preReadTransaction:transaction];
			block(transaction);
			[self postReadTransaction:transaction];
		}
		
		if (completionBlock)
			dispatch_async(completionQueue, completionBlock);
	}});
}

/**
 * Read-write access to the database.
 *
 * Only a single read-write block can execute among all sibling connections.
 * Thus the execution of the block may be delayted if another sibling connection
 * is currently executing a read-write block.
 *
 * This method is asynchronous.
**/
- (void)_asyncReadWriteWithBlock:(void (^)(id))block
                 completionBlock:(dispatch_block_t)completionBlock
                 completionQueue:(dispatch_queue_t)completionQueue
{
	if (completionQueue == NULL && completionBlock != NULL)
		completionQueue = dispatch_get_main_queue();
	
	// Order matters.
	// First go through the serial connection queue.
	// Then go through serial write queue for the database.
	//
	// Once we're inside the database writeQueue, we know that we are the only write transaction.
	// No other transaction can possibly modify the database except us, even in other connections.
	
	dispatch_async(connectionQueue, ^{
		
		if (longLivedReadTransaction)
		{
			YDBLogWarn(@"Implicitly ending long-lived read transaction on connection %@, database %@",
			           self, database);
			
			[self endLongLivedReadTransaction];
		}
		
		__preWriteQueue(self);
		dispatch_sync(database->writeQueue, ^{ @autoreleasepool {
			
			YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
			
			[self preReadWriteTransaction:transaction];
			block(transaction);
			[self postReadWriteTransaction:transaction];
			
			if (completionBlock)
				dispatch_async(completionQueue, completionBlock);
			
		}}); // End dispatch_sync(database->writeQueue)
		__postWriteQueue(self);
	});      // End dispatch_async(connectionQueue)
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapAbstractDatabaseTransaction *)newReadTransaction
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

/**
 * This method executes the state transition steps required before executing a read-only transaction block.
 * 
 * This method must be invoked from within the connectionQueue.
**/
- (void)preReadTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	// Pre-Read-Transaction: Step 1 of 3
	//
	// Execute "BEGIN TRANSACTION" on database connection.
	// This is actually a deferred transaction, meaning the sqlite connection won't actually
	// acquire a shared read lock until it executes a select statement.
	// There are alternatives to this, including a "begin immediate transaction".
	// However, this doesn't do what we want. Instead it blocks other read-only transactions.
	// The deferred transaction is actually what we want, as many read-only transactions only
	// hit our in-memory caches. Thus we avoid sqlite machinery when unneeded.
	
	[transaction beginTransaction];
		
	dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
		
		// Pre-Read-Transaction: Step 2 of 3
		//
		// Update our connection state within the state table.
		//
		// First we need to mark this connection as being within a read-only transaction.
		// We do this by marking a "yap-level" shared read lock flag.
		//
		// Now recall from step 1 that our "sql-level" transaction is deferred.
		// The sql internals won't actually acquire the shared read lock until a we perform a select.
		// If there are write transactions in progress, this is a big problem for us.
		// Here's why:
		//
		// We have an in-memory snapshot via the caches.
		// This is kept in-sync with what's on disk (in the sqlite database file).
		// But what happens if the write transaction commits its changes before we perform our select statement?
		// Our select statement would acquire a different snapshot than our in-memory snapshot.
		// Thus, we look to see if there are any write transactions.
		// If there are, then we immediately acquire the "sql-level" shared read lock.
		
		BOOL hasActiveWriteTransaction = NO;
		YapDatabaseConnectionState *myState = nil;
		
		for (YapDatabaseConnectionState *state in database->connectionStates)
		{
			if (state->connection == self)
			{
				myState = state;
				myState->yapLevelSharedReadLock = YES;
			}
			else if (state->yapLevelExclusiveWriteLock)
			{
				hasActiveWriteTransaction = YES;
			}
		}
		
		NSAssert(myState != nil, @"Missing state in database->connectionStates");
		
		// Pre-Read-Transaction: Step 3 of 3
		//
		// Update our in-memory data (caches, etc) if needed.
		
		if (hasActiveWriteTransaction || longLivedReadTransaction)
		{
			// If this is for a longLivedReadTransaction,
			// then we need to immediately acquire a "sql-level" snapshot.
			//
			// Otherwise if there is a write transaction in progress,
			// then it's not safe to proceed until we acquire a "sql-level" snapshot.
			//
			// During this process we need to ensure that our "yap-level" snapshot of the in-memory data (caches, etc)
			// is in sync with our "sql-level" snapshot of the database.
			//
			// We can check this by comparing the connection's snapshot ivar with
			// the snapshot read from disk (via sqlite select).
			//
			// If the two match then our snapshots are in sync.
			// If they don't then we need to get caught up by processing changesets.
			
			uint64_t yapSnapshot = snapshot;
			uint64_t sqlSnapshot = [self readSnapshotFromDatabase];
			
			if (yapSnapshot < sqlSnapshot)
			{
				// The transaction can see the sqlite commit from another transaction,
				// and it hasn't processed the changeset(s) yet. We need to process them now.
				
				NSArray *changesets = [database pendingAndCommittedChangesSince:yapSnapshot until:sqlSnapshot];
				
				for (NSDictionary *changeset in changesets)
				{
					[self noteCommittedChanges:changeset];
				}
				
				NSAssert(snapshot == sqlSnapshot,
				         @"Invalid connection state in preReadTransaction: snapshot(%llu) != sqlSnapshot(%llu): %@",
				         snapshot, sqlSnapshot, changesets);
			}
			
			myState->lastKnownSnapshot = snapshot;
			myState->longLivedReadTransaction = (longLivedReadTransaction != nil);
			myState->sqlLevelSharedReadLock = YES;
			needsMarkSqlLevelSharedReadLock = NO;
		}
		else
		{
			// There is NOT a write transaction in progress.
			// Thus we are safe to proceed with only a "yap-level" snapshot.
			//
			// However, we MUST ensure that our "yap-level" snapshot of the in-memory data (caches, etc)
			// are in sync with the rest of the system.
			//
			// That is, our connection may have started its transaction before it was
			// able to process a changeset from a sibling connection.
			// If this is the case then we need to get caught up by processing the changeset(s).
			
			uint64_t localSnapshot = snapshot;
			uint64_t globalSnapshot = [database snapshot];
			
			if (localSnapshot < globalSnapshot)
			{
				// The transaction hasn't processed recent changeset(s) yet. We need to process them now.
				
				NSArray *changesets = [database pendingAndCommittedChangesSince:localSnapshot until:globalSnapshot];
				
				for (NSDictionary *changeset in changesets)
				{
					[self noteCommittedChanges:changeset];
				}
				
				NSAssert(snapshot == globalSnapshot,
				         @"Invalid connection state in preReadTransaction: snapshot(%llu) != globalSnapshot(%llu): %@",
				         snapshot, globalSnapshot, changesets);
			}
			
			myState->lastKnownSnapshot = snapshot;
			myState->sqlLevelSharedReadLock = NO;
			needsMarkSqlLevelSharedReadLock = YES;
		}
	}});
}

/**
 * This method executes the state transition steps required after executing a read-only transaction block.
 *
 * This method must be invoked from within the connectionQueue.
**/
- (void)postReadTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	// Post-Read-Transaction: Step 1 of 4
	//
	// 1. Execute "COMMIT TRANSACTION" on database connection.
	// If we had acquired "sql-level" shared read lock, this will release associated resources.
	// It may also free the auto-checkpointing architecture within sqlite to sync the WAL to the database.
	
	[transaction commitTransaction];
	
	__block uint64_t minSnapshot = 0;
	__block YapDatabaseConnectionState *writeStateToSignal = nil;
	
	dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
		
		// Post-Read-Transaction: Step 2 of 4
		//
		// Update our connection state within the state table.
		//
		// First we need to mark this connection as no longer being within a read-only transaction.
		// We do this by unmarking the "yap-level" and "sql-level" shared read lock flags.
		//
		// While we're doing this we also check to see if we were possibly blocking a write transaction.
		// When does a write transaction get blocked?
		//
		// Recall from the discussion above that we don't always acquire a "sql-level" shared read lock.
		// Our sql transaction is deferred until our first select statement.
		// Now if a write transaction comes along and discovers there are existing read transactions that
		// have an in-memory metadata snapshot, but haven't acquired an "sql-level" snapshot of the actual
		// database, it will block until these read transctions either complete,
		// or acquire the needed "sql-level" snapshot.
		//
		// So if we never acquired an "sql-level" snapshot of the database, and we were the last transaction
		// in such a state, and there's a blocked write transaction, then we need to signal it.
		
		minSnapshot = [database snapshot];
		
		BOOL wasMaybeBlockingWriteTransaction = NO;
		NSUInteger countOtherMaybeBlockingWriteTransaction = 0;
		YapDatabaseConnectionState *blockedWriteState = nil;
		
		for (YapDatabaseConnectionState *state in database->connectionStates)
		{
			if (state->connection == self)
			{
				wasMaybeBlockingWriteTransaction = state->yapLevelSharedReadLock && !state->sqlLevelSharedReadLock;
				state->yapLevelSharedReadLock = NO;
				state->sqlLevelSharedReadLock = NO;
				state->longLivedReadTransaction = NO;
			}
			else if (state->yapLevelSharedReadLock)
			{
				// Active sibling connection: read-only
				
				minSnapshot = MIN(state->lastKnownSnapshot, minSnapshot);
				
				if (!state->sqlLevelSharedReadLock)
					countOtherMaybeBlockingWriteTransaction++;
			}
			else if (state->yapLevelExclusiveWriteLock)
			{
				// Active sibling connection: read-write
				
				minSnapshot = MIN(state->lastKnownSnapshot, minSnapshot);
				
				if (state->waitingForWriteLock)
					blockedWriteState = state;
			}
		}
		
		if (wasMaybeBlockingWriteTransaction && countOtherMaybeBlockingWriteTransaction == 0 && blockedWriteState)
		{
			writeStateToSignal = blockedWriteState;
		}
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) completing read-only transaction.", self);
	}});
	
	// Post-Read-Transaction: Step 3 of 4
	//
	// Check to see if this connection has been holding back the checkpoint process.
	// That is, was this connection the last active connection on an old snapshot?
	
	if (snapshot < minSnapshot)
	{
		// There are commits ahead of us that need to be checkpointed.
		// And we were the oldest active connection,
		// so we were previously preventing the checkpoint from progressing.
		// Thus we can now continue the checkpoint operation.
		
		[database asyncCheckpoint:minSnapshot];
	}
	
	// Post-Read-Transaction: Step 4 of 4
	//
	// If we discovered a blocked write transaction,
	// and it was blocked waiting on us (because we had a "yap-level" snapshot without an "sql-level" snapshot),
	// and it's no longer blocked on any other read transaction (that have "yap-level" snapshots
	// without "sql-level snapshots"), then signal the write semaphore so the blocked thread wakes up.
	
	if (writeStateToSignal)
	{
		YDBLogVerbose(@"YapDatabaseConnection(%p) signaling blocked write on connection(%p)",
		                                    self, writeStateToSignal->connection);
		
		[writeStateToSignal signalWriteLock];
	}
}

/**
 * This method executes the state transition steps required before executing a read-write transaction block.
 * 
 * This method must be invoked from within the connectionQueue.
 * This method must be invoked from within the database.writeQueue.
**/
- (void)preReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	// Pre-Write-Transaction: Step 1 of 4
	//
	// Execute "BEGIN TRANSACTION" on database connection.
	// This is actually a deferred transaction, meaning the sqlite connection won't actually
	// acquire any locks until it executes something.
	// There are various alternatives to this, including a "immediate" and "exclusive" transactions.
	// However, these don't do what we want. Instead they block other read-only transactions.
	// The deferred transaction allows other read-only transactions and even avoids
	// sqlite operations if no modifications are made.
	//
	// Remember, we are the only active write transaction for this database.
	// No other write transactions can occur until this transaction completes.
	// Thus no other transactions can possibly modify the database during our transaction.
	// Therefore it doesn't matter when we acquire our "sql-level" locks for writing.
	
	[transaction beginTransaction];
	
	dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
		
		// Pre-Write-Transaction: Step 2 of 4
		//
		// Update our connection state within the state table.
		//
		// We are the only write transaction for this database.
		// It is important for read-only transactions on other connections to know there's a writer.
		
		YapDatabaseConnectionState *myState = nil;
		
		for (YapDatabaseConnectionState *state in database->connectionStates)
		{
			if (state->connection == self)
			{
				myState = state;
				myState->yapLevelExclusiveWriteLock = YES;
			}
		}
		
		NSAssert(myState != nil, @"Missing state in database->connectionStates");
		
		// Pre-Write-Transaction: Step 3 of 4
		//
		// Validate our caches based on snapshot numbers
		
		uint64_t localSnapshot = snapshot;
		uint64_t globalSnapshot = [database snapshot];
		
		if (localSnapshot < globalSnapshot)
		{
			NSArray *changesets = [database pendingAndCommittedChangesSince:localSnapshot until:globalSnapshot];
			
			for (NSDictionary *changeset in changesets)
			{
				[self noteCommittedChanges:changeset];
			}
			
			NSAssert(snapshot == globalSnapshot,
			         @"Invalid connection state in preReadWriteTransaction: snapshot(%llu) != globalSnapshot(%llu)",
			         snapshot, globalSnapshot);
		}
		
		myState->lastKnownSnapshot = snapshot;
		needsMarkSqlLevelSharedReadLock = NO;
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) starting read-write transaction.", self);
	}});
	
	// Pre-Write-Transaction: Step 4 of 4
	//
	// Add IsOnConnectionQueueKey flag to writeQueue.
	// This allows various methods that depend on the flag to operate correctly.
	
	dispatch_queue_set_specific(database->writeQueue, IsOnConnectionQueueKey, IsOnConnectionQueueKey, NULL);
}

/**
 * This method executes the state transition steps required after executing a read-only transaction block.
 *
 * This method must be invoked from within the connectionQueue.
 * This method must be invoked from within the database.writeQueue.
**/
- (void)postReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	if (transaction->rollback)
	{
		// Rollback-Write-Transaction: Step 1 of 2
		//
		// Update our connection state within the state table.
		//
		// We are the only write transaction for this database.
		// It is important for read-only transactions on other connections to know we're no longer a writer.
		
		dispatch_sync(database->snapshotQueue, ^{
		
			for (YapDatabaseConnectionState *state in database->connectionStates)
			{
				if (state->connection == self)
				{
					state->yapLevelExclusiveWriteLock = NO;
					break;
				}
			}
		});
		
		// Rollback-Write-Transaction: Step 2 of 3
		//
		// Rollback sqlite database transaction.
		
		[transaction rollbackTransaction];
		
		// Rollback-Write-Transaction: Step 3 of 3
		//
		// Reset any in-memory variables which may be out-of-sync with the database.
		
		[self postRollbackCleanup];
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) completing read-write transaction (rollback).", self);
		
		return;
	}
	
	// Post-Write-Transaction: Step 1 of 11
	//
	// Run any pre-commit operations.
	// This allows extensions to to perform any cleanup before the changeset is requested.
	
	[transaction preCommitReadWriteTransaction];
	
	// Post-Write-Transaction: Step 2 of 11
	//
	// Fetch changesets.
	// Then update the snapshot in the 'yap' database (if any changes were made).
	// We use 'yap' database and snapshot value to check for a race condition.
	//
	// The "internal" changeset gets sent directly to sibling database connections.
	// The "external" changeset gets plugged into the YapDatabaseModifiedNotification as the userInfo dict.
	
	NSNotification *notification = nil;
	
	NSMutableDictionary *changeset = nil;
	NSMutableDictionary *userInfo = nil;
	
	[self getInternalChangeset:&changeset externalChangeset:&userInfo];
	if (changeset)
	{
		snapshot = [self incrementSnapshotInDatabase];
		
		[changeset setObject:@(snapshot) forKey:@"snapshot"];
		
		if (userInfo == nil)
			userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
		
		[userInfo setObject:self forKey:YapDatabaseConnectionKey];
		
		if (transaction->customObjectForNotification)
			[userInfo setObject:transaction->customObjectForNotification forKey:YapDatabaseCustomKey];
		
		notification = [NSNotification notificationWithName:YapDatabaseModifiedNotification
		                                             object:database
		                                           userInfo:userInfo];
		
		[changeset setObject:notification forKey:@"notification"];
	}
	
	// Post-Write-Transaction: Step 3 of 11
	//
	// Auto-drop tables from previous extensions that aren't being used anymore.
	//
	// Note the timing of when this happens:
	// - Only once
	// - At the end of a readwrite transaction that has made modifications to the database
	// - Only if the modifications weren't dedicated to registering/unregistring an extension
	
	if (database->previouslyRegisteredExtensionNames && changeset && !registeredExtensionsChanged)
	{
		for (NSString *prevExtensionName in database->previouslyRegisteredExtensionNames)
		{
			if ([registeredExtensions objectForKey:prevExtensionName] == nil)
			{
				NSString *className = [transaction stringValueForKey:@"class" extension:prevExtensionName];
				Class class = NSClassFromString(className);
				
				if (className == nil)
				{
					YDBLogWarn(@"Unable to auto-unregister extension(%@). Doesn't appear to be registered.",
					           prevExtensionName);
				}
				else if (class == NULL)
				{
					YDBLogError(@"Unable to auto-unregister extension(%@) with unknown class(%@)",
					            prevExtensionName, className);
				}
				if (![class isSubclassOfClass:[YapAbstractDatabaseExtension class]])
				{
					YDBLogError(@"Unable to auto-unregister extension(%@) with improper class(%@)",
					            prevExtensionName, className);
				}
				else
				{
					YDBLogInfo(@"Auto-unregistering extension(%@) with class(%@)",
					            prevExtensionName, className);
					
					// Drop tables
					[class dropTablesForRegisteredName:prevExtensionName withTransaction:transaction];
					
					// Drop preferences (rows in yap2 table)
					[transaction removeAllValuesForExtension:prevExtensionName];
				}
			}
		}
		
		database->previouslyRegisteredExtensionNames = nil;
	}
	
	// Post-Write-Transaction: Step 4 of 11
	//
	// Check to see if it's safe to commit our changes.
	//
	// There may be read-only transactions that have acquired "yap-level" snapshots
	// without "sql-level" snapshots. That is, these read-only transaction may have a snapshot
	// of the in-memory metadata dictionary at the time they started, but as for the sqlite connection
	// the only have a "BEGIN DEFERRED TRANSACTION", and haven't actually executed
	// any "select" statements. Thus they haven't actually invoked the sqlite machinery to
	// acquire the "sql-level" snapshot (last valid commit record in the WAL).
	//
	// It is our responsibility to block until all read-only transactions have either completed,
	// or have acquired the necessary "sql-level" shared read lock.
	//
	// We avoid writer starvation by enforcing new read-only transactions that start after our writer
	// started to immediately acquire "sql-level" shared read locks when they start.
	// Thus we would only ever wait for read-only transactions that started before our
	// read-write transaction started. And since most of the time the read-write transactions
	// take longer than read-only transactions, we avoid any blocking in most cases.
	
	__block YapDatabaseConnectionState *myState = nil;
	__block BOOL safeToCommit = NO;
	
	do
	{
		__block BOOL waitForReadOnlyTransactions = NO;
		
		dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
			
			for (YapDatabaseConnectionState *state in database->connectionStates)
			{
				if (state->connection == self)
				{
					myState = state;
				}
				else if (state->yapLevelSharedReadLock && !state->sqlLevelSharedReadLock)
				{
					waitForReadOnlyTransactions = YES;
				}
			}
			
			NSAssert(myState != nil, @"Missing state in database->connectionStates");
			
			if (waitForReadOnlyTransactions)
			{
				myState->waitingForWriteLock = YES;
				[myState prepareWriteLock];
			}
			else
			{
				myState->waitingForWriteLock = NO;
				safeToCommit = YES;
				
				// Post-Write-Transaction: Step 5 of 11
				//
				// Register pending changeset with database.
				// Our commit is actually a two step process.
				// First we execute the sqlite level commit.
				// Second we execute the final stages of the yap level commit.
				//
				// This two step process means we have an edge case,
				// where another connection could come around and begin its yap level transaction
				// before this connections yap level commit, but after this connections sqlite level commit.
				//
				// By registering the pending changeset in advance,
				// we provide a near seamless workaround for the edge case.
				
				if (changeset)
				{
					[database notePendingChanges:changeset fromConnection:self];
				}
			}
			
		}});
		
		if (waitForReadOnlyTransactions)
		{
			// Block until a read-only transaction signals us.
			// This will occur when the last read-only transaction (that started before our read-write
			// transaction started) either completes or acquires an "sql-level" shared read lock.
			//
			// Note: Since we're using a dispatch semaphore, order doesn't matter.
			// That is, it's fine if the read-only transaction signals our write lock before we start waiting on it.
			// In this case we simply return immediately from the wait call.
			
			YDBLogVerbose(@"YapDatabaseConnection(%p) blocked waiting for write lock...", self);
			
			[myState waitForWriteLock];
		}
		
	} while (!safeToCommit);
	
	// Post-Write-Transaction: Step 6 of 11
	//
	// Execute "COMMIT TRANSACTION" on database connection.
	// This will write the changes to the WAL, and may invoke a checkpoint.
	//
	// Notice that we do this outside the context of the transactionStateQueue.
	// We do this so we don't block read-only transactions from starting or finishing.
	// However, this does leave us open for the possibility that a read-only transaction will
	// get a "yap-level" snapshot of the metadata dictionary before this commit,
	// but a "sql-level" snapshot of the sql database after this commit.
	// This is rare but must be guarded against.
	// The solution is pretty simple and straight-forward.
	// When a read-only transaction starts, if there's an active write transaction,
	// it immediately acquires an "sql-level" snapshot. It does this by invoking a select statement,
	// which invokes the internal sqlite snapshot machinery for the transaction.
	// So rather than using a dummy select statement that we ignore, we instead select a lastCommit number
	// from the database. If it doesn't match what we expect, then we know we've run into the race condition,
	// and we make the read-only transaction back out and try again.
	
	[transaction commitTransaction];
	
	__block uint64_t minSnapshot = UINT64_MAX;
	
	dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
		
		// Post-Write-Transaction: Step 7 of 11
		//
		// Notify database of changes, and drop reference to set of changed keys.
		
		if (changeset)
		{
			[database noteCommittedChanges:changeset fromConnection:self];
		}
		
		// Post-Write-Transaction: Step 8 of 11
		//
		// Update our connection state within the state table.
		//
		// We are the only write transaction for this database.
		// It is important for read-only transactions on other connections to know we're no longer a writer.
		
		for (YapDatabaseConnectionState *state in database->connectionStates)
		{
			if (state->yapLevelSharedReadLock)
			{
				minSnapshot = MIN(state->lastKnownSnapshot, minSnapshot);
			}
		}
		
		myState->yapLevelExclusiveWriteLock = NO;
		myState->waitingForWriteLock = NO;
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) completing read-write transaction.", self);
	}});
	
	// Post-Write-Transaction: Step 9 of 11
	
	if (changeset)
	{
		// We added frames to the WAL.
		// We can invoke a checkpoint if there are no other active connections.
		
		if (minSnapshot == UINT64_MAX)
		{
			[database asyncCheckpoint:snapshot];
		}
	}
	
	// Post-Write-Transaction: Step 10 of 11
	//
	// Post YapDatabaseModifiedNotification
	
	if (notification)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotification:notification];
		});
	}
	
	// Post-Write-Transaction: Step 11 of 11
	//
	// Drop IsOnConnectionQueueKey flag from writeQueue since we're exiting writeQueue.
	
	dispatch_queue_set_specific(database->writeQueue, IsOnConnectionQueueKey, NULL, NULL);
}

/**
 * This method "kills two birds with one stone".
 * 
 * First, it invokes a SELECT statement on the database.
 * This executes the sqlite machinery to acquire a "sql-level" snapshot of the database.
 * That is, the encompassing transaction will now reference a specific commit record in the WAL,
 * and will ignore any commits made after this record.
 * 
 * Second, it reads a specific value from the database, and tells us which commit record in the WAL its using.
 * This allows us to validate the transaction, and check for a particular race condition.
**/
- (uint64_t)readSnapshotFromDatabase
{
	sqlite3_stmt *statement = [self yapGetDataForKeyStatement];
	if (statement == NULL) return 0.0;
	
	uint64_t result = 0;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	char *extension = "";
	sqlite3_bind_text(statement, 1, extension, (int)strlen(extension), SQLITE_STATIC);
	
	char *key = "snapshot";
	sqlite3_bind_text(statement, 2, key, (int)strlen(key), SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = (uint64_t)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return result;
}

/**
 * This method updates the 'snapshot' row in the database.
**/
- (uint64_t)incrementSnapshotInDatabase
{
	uint64_t newSnapshot = snapshot + 1;
	
	sqlite3_stmt *statement = [self yapSetDataForKeyStatement];
	if (statement == NULL) return newSnapshot;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	char *extension = "";
	sqlite3_bind_text(statement, 1, extension, (int)strlen(extension), SQLITE_STATIC);
	
	char *key = "snapshot";
	sqlite3_bind_text(statement, 2, key, (int)strlen(key), SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, 3, (sqlite3_int64)newSnapshot);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return newSnapshot;
}

- (void)markSqlLevelSharedReadLockAcquired
{
	NSAssert(needsMarkSqlLevelSharedReadLock, @"Method called but unneeded. Unnecessary overhead.");
	if (!needsMarkSqlLevelSharedReadLock) return;
	
	__block YapDatabaseConnectionState *writeStateToSignal = nil;
	
	dispatch_sync(database->snapshotQueue, ^{ @autoreleasepool {
		
		// Update our connection state within the state table.
		//
		// We need to mark this connection as having acquired an "sql-level" shared read lock.
		// That is, our sqlite connection has invoked a select statement, and has thus invoked the sqlite
		// machinery that causes it to acquire the "sql-level" snapshot (last valid commit record in the WAL).
		//
		// While we're doing this we also check to see if we were possibly blocking a write transaction.
		// When does a write transaction get blocked?
		//
		// If a write transaction goes to commit its changes and sees a read-only transaction with
		// a "yap-level" snapshot of the in-memory metadata snapshot, but without an "sql-level" snapshot
		// of the actual database, it will block until these read transctions either complete,
		// or acquire the needed "sql-level" snapshot.
		//
		// So if we never acquired an "sql-level" snapshot of the database, and we were the last transaction
		// in such a state, and there's a blocked write transaction, then we need to signal it.
		
		__block NSUInteger countOtherMaybeBlockingWriteTransaction = 0;
		__block YapDatabaseConnectionState *blockedWriteState = nil;
		
		for (YapDatabaseConnectionState *state in database->connectionStates)
		{
			if (state->connection == self)
			{
				state->sqlLevelSharedReadLock = YES;
			}
			else if (state->yapLevelSharedReadLock && !state->sqlLevelSharedReadLock)
			{
				countOtherMaybeBlockingWriteTransaction++;
			}
			else if (state->waitingForWriteLock)
			{
				blockedWriteState = state;
			}
		}
		
		if (countOtherMaybeBlockingWriteTransaction == 0 && blockedWriteState)
		{
			writeStateToSignal = blockedWriteState;
		}
	}});
	
	needsMarkSqlLevelSharedReadLock = NO;
	
	if (writeStateToSignal)
	{
		YDBLogVerbose(@"YapDatabaseConnection(%p) signaling blocked write on connection(%p)",
											 self, writeStateToSignal->connection);
		[writeStateToSignal signalWriteLock];
	}
}

/**
 * This method is invoked after a read-write transaction completes, which was rolled-back.
 * You should flush anything from memory that may be out-of-sync with the database.
 * 
 * If you override this method, be sure to invoke [super postRollbackCleanup]
**/
- (void)postRollbackCleanup
{
	[objectCache removeAllObjects];
	[metadataCache removeAllObjects];
	
	// Use existing extensions (extensions ivar, not [self extensions]).
	// There's no need to create any new extConnections at this point.
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extConnectionObj, BOOL *stop) {
		
		[(YapAbstractDatabaseExtensionConnection *)extConnectionObj postRollbackCleanup];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * REQUIRED OVERRIDE HOOK.
 *
 * This method is invoked from within the postReadWriteTransaction operation.
 * This method is invoked before anything has been committed.
 *
 * If changes have been made, it should return a changeset dictionary.
 * If no changes have been made, it should return nil.
 * 
 * Subclasses must first invoke super in order to get the changesets from the extensions.
 * 
 * @see processChangeset:
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary **)externalChangesetPtr
{
	// Use existing extensions (extensions ivar, not [self extensions]).
	// There's no need to create any new extConnections at this point.
	
	__block NSMutableDictionary *internalChangeset_extensions = nil;
	__block NSMutableDictionary *externalChangeset_extensions = nil;
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id extName, id extConnectionObj, BOOL *stop) {
		
		__unsafe_unretained YapAbstractDatabaseExtensionConnection *extConnection = extConnectionObj;
		
		NSMutableDictionary *internal = nil;
		NSMutableDictionary *external = nil;
		
		[extConnection getInternalChangeset:&internal externalChangeset:&external];
		
		if (internal)
		{
			if (internalChangeset_extensions == nil)
				internalChangeset_extensions = [NSMutableDictionary dictionaryWithCapacity:[extensions count]];
			
			[internalChangeset_extensions setObject:internal forKey:extName];
		}
		if (external)
		{
			if (externalChangeset_extensions == nil)
				externalChangeset_extensions = [NSMutableDictionary dictionaryWithCapacity:[extensions count]];
			
			[externalChangeset_extensions setObject:external forKey:extName];
		}
	}];
	
	NSMutableDictionary *internalChangeset = nil;
	NSMutableDictionary *externalChangeset = nil;
	
	if (internalChangeset_extensions)
	{
		internalChangeset = [NSMutableDictionary dictionaryWithCapacity:8];
		[internalChangeset setObject:internalChangeset_extensions forKey:@"extensions"];
	}
	
	if (externalChangeset_extensions)
	{
		externalChangeset = [NSMutableDictionary dictionaryWithCapacity:8];
		[externalChangeset setObject:externalChangeset_extensions forKey:YapDatabaseExtensionsKey];
	}
	
	if (registeredExtensionsChanged)
	{
		if (internalChangeset == nil)
			internalChangeset = [NSMutableDictionary dictionaryWithCapacity:8];
		
		[internalChangeset setObject:registeredExtensions forKey:@"registeredExtensions"];
	}
	
	*internalChangesetPtr = internalChangeset;
	*externalChangesetPtr = externalChangeset;
}

/**
 * REQUIRED OVERRIDE HOOK.
 * 
 * This method is invoked with the changeset from a sibling connection.
 * The connection should update any in-memory components (such as the cache) to properly reflect the changeset.
 * 
 * Subclasses must invoke [super processChangeset:changeset] in order to propogate the changeset(s) to the extension(s).
 *
 * @see getInternalChangeset:externalChangeset:
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	NSDictionary *changeset_registeredExtensions = [changeset objectForKey:@"registeredExtensions"];
	if (changeset_registeredExtensions)
	{
		// Retain new list
		
		registeredExtensions = changeset_registeredExtensions;
		
		// Remove any extensions that have been dropped
		
		for (NSString *extName in [extensions allKeys])
		{
			if ([registeredExtensions objectForKey:extName] == nil)
			{
				YDBLogVerbose(@"Dropping extension: %@", extName);
				
				[extensions removeObjectForKey:extName];
			}
		}
		
		// Make a note if there are extensions for which we haven't instantiated an extConnection instance.
		// We lazily load these later, if needed.
		
		extensionsReady = ([registeredExtensions count] == [extensions count]);
	}
	
	NSDictionary *changeset_extensions = [changeset objectForKey:@"extensions"];
	if (changeset_extensions)
	{
		// Use existing extensions (extensions ivar, not [self extensions]).
		// There's no need to create any new extConnections at this point.
		
		[extensions enumerateKeysAndObjectsUsingBlock:^(id extName, id extConnectionObj, BOOL *stop) {
			
			__unsafe_unretained YapAbstractDatabaseExtensionConnection *extConnection = extConnectionObj;
			
			NSDictionary *changeset_extensions_extName = [changeset_extensions objectForKey:extName];
			if (changeset_extensions_extName)
			{
				[extConnection processChangeset:changeset_extensions_extName];
			}
		}];
	}
}

/**
 * Internal method. Do not override.
 *
 * This method is invoked with the changeset from a sibling connection.
**/
- (void)noteCommittedChanges:(NSDictionary *)changeset
{
	// This method must be invoked from within connectionQueue.
	// It may be invoked from:
	//
	// 1. [database noteCommittedChanges:fromConnection:]
	//   via dispatch_async(connectionQueue, ...)
	//
	// 2. [self  preReadTransaction:]
	//   via dispatch_X(connectionQueue) -> dispatch_sync(database->snapshotQueue)
	//
	// 3. [self preReadWriteTransaction:]
	//   via dispatch_X(connectionQueue) -> dispatch_sync(database->snapshotQueue)
	//
	// In case 1 (the common case) we can see IsOnConnectionQueueKey.
	// In case 2 & 3 (the edge cases) we can see IsOnSnapshotQueueKey.
	
	NSAssert(dispatch_get_specific(IsOnConnectionQueueKey) ||
			 dispatch_get_specific(database->IsOnSnapshotQueueKey), @"Must be invoked within connectionQueue");
	
	// Grab the new snapshot.
	// This tells us the minimum snapshot we could get if we started a transaction right now.
	
	uint64_t changesetSnapshot = [[changeset objectForKey:@"snapshot"] unsignedLongLongValue];
	
	if (changesetSnapshot <= snapshot)
	{
		// We already noted this changeset.
		//
		// There is a "race condition" that occasionally happens when a readonly transaction is started
		// around the same instant a readwrite transaction finishes committing its changes to disk.
		// The readonly transaction enters our transaction state queue (to start) before
		// the readwrite transaction enters our transaction state queue (to finish).
		// However the readonly transaction gets a database snapshot post readwrite commit.
		// That is, the readonly transaction can read the changes from the readwrite transaction at the sqlite layer,
		// even though the readwrite transaction hasn't completed within the yap database layer.
		//
		// This race condition is handled automatically within the preReadTransaction method.
		// In fact, it invokes this method to handle the race condition.
		// Thus this method could be invoked twice to handle the same changeset.
		// So catching it here and ignoring it is simply a minor optimization to avoid duplicate work.
		
		YDBLogVerbose(@"Ignoring previously processed changeset %lu for connection %@, database %@",
		              (unsigned long)changesetSnapshot, self, self->database);
		
		return;
	}
	
	if (longLivedReadTransaction)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
		{
			// This method is being invoked from preReadTransaction:.
			// We are to process the changeset for it.
			
			[processedChangesets addObject:changeset];
		}
		else
		{
			// This method is being invoked from [database noteCommittedChanges:].
			// We cannot process the changeset yet.
			// We must wait for the longLivedReadTransaction to be reset.
			
			YDBLogVerbose(@"Storing pending changeset %lu for connection %@, database %@",
			              (unsigned long)changesetSnapshot, self, self->database);
			
			[pendingChangesets addObject:changeset];
			return;
		}
	}
	
	// Changeset processing
	
	YDBLogVerbose(@"Processing changeset %lu for connection %@, database %@",
	              (unsigned long)changesetSnapshot, self, self->database);
	
	snapshot = changesetSnapshot;
	[self processChangeset:changeset];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Long-lived read transactions are a great way to achive stability, especially in places like the main-thread.
 * However, they pose a unique problem. These long-lived transactions often start out by
 * locking the WAL (write ahead log). This prevents the WAL from ever getting reset,
 * and thus causes the WAL to potentially grow infinitely large. In order to allow the WAL to get properly reset,
 * we need the long-lived read transactions to "reset". That is, without changing their stable state (their snapshot),
 * we need them to restart the transaction, but this time without locking this WAL.
 * 
 * We use the maybeResetLongLivedReadTransaction method to achieve this.
**/
- (void)maybeResetLongLivedReadTransaction
{
	// Async dispatch onto the writeQueue so we know there aren't any other active readWrite transactions
	
	dispatch_async(database->writeQueue, ^{
		
		// Pause the writeQueue so readWrite operations can't interfere with us.
		// We abort if our connection has a readWrite transaction pending.
		
		BOOL abort = NO;
		
		OSSpinLockLock(&lock);
		{
			if (activeReadWriteTransaction) {
				abort = YES;
			}
			else if (!writeQueueSuspended) {
				dispatch_suspend(database->writeQueue);
				writeQueueSuspended = YES;
			}
		}
		OSSpinLockUnlock(&lock);
		
		if (abort) return;
		
		// Async dispatch onto our connectionQueue.
		
		dispatch_async(connectionQueue, ^{
			
			// If possible, silently reset the longLivedReadTransaction (same snapshot, no longer locking the WAL)
			
			if (longLivedReadTransaction && (snapshot == [database snapshot]))
			{
				NSArray *empty = [self beginLongLivedReadTransaction];
				
				if ([empty count] != 0)
				{
					YDBLogError(@"Core logic failure! "
					            @"Silent longLivedReadTransaction reset resulted in non-empty notification array!");
				}
			}
			
			// Resume the writeQueue
			
			OSSpinLockLock(&lock);
			{
				if (writeQueueSuspended) {
					dispatch_resume(database->writeQueue);
					writeQueueSuspended = NO;
				}
			}
			OSSpinLockUnlock(&lock);
		});
	});
}

NS_INLINE void __preWriteQueue(YapAbstractDatabaseConnection *connection)
{
	OSSpinLockLock(&connection->lock);
	{
		if (connection->writeQueueSuspended) {
			dispatch_resume(connection->database->writeQueue);
			connection->writeQueueSuspended = NO;
		}
		connection->activeReadWriteTransaction = YES;
	}
	OSSpinLockUnlock(&connection->lock);
}

NS_INLINE void __postWriteQueue(YapAbstractDatabaseConnection *connection)
{
	OSSpinLockLock(&connection->lock);
	{
		connection->activeReadWriteTransaction = NO;
	}
	OSSpinLockUnlock(&connection->lock);
}

@end
