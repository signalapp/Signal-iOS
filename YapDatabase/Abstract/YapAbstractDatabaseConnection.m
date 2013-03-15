#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Does ARC support support GCD objects?
 * It does if the minimum deployment target is iOS 6+ or Mac OS X 10.8+
**/
#if TARGET_OS_IPHONE

  // Compiling for iOS

  #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000 // iOS 6.0 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else                                         // iOS 5.X or earlier
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1
  #endif

#else

  // Compiling for Mac OS X

  #if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080     // Mac OS X 10.8 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1     // Mac OS X 10.7 or earlier
  #endif

#endif

/**
 * Define log level for this file.
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapAbstractDatabaseConnection {

/* As declared in YapAbstractDatabasePrivate.h :

@private
	sqlite3_stmt *beginTransactionStatement;
	sqlite3_stmt *commitTransactionStatement;
	
	sqlite3_stmt *yapGetDataForKeyStatement; // Against "yap" database, for internal use
	sqlite3_stmt *yapSetDataForKeyStatement; // Against "yap" database, for internal use
	
@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
	NSTimeInterval cacheLastWriteTimestamp;
	
@public
	sqlite3 *db;
	
	YapSharedCacheConnection *objectCache;
	YapSharedCacheConnection *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL hasMarkedSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.

*/
}

- (id)initWithDatabase:(YapAbstractDatabase *)inDatabase
{
	if ((self = [super init]))
	{
		database = inDatabase;
		connectionQueue = dispatch_queue_create("YapDatabaseConnection", NULL);
		
		IsOnConnectionQueueKey = &IsOnConnectionQueueKey;
		void *nonNullUnusedPointer = (__bridge void *)self;
		dispatch_queue_set_specific(connectionQueue, IsOnConnectionQueueKey, nonNullUnusedPointer, NULL);
		
		objectCacheLimit = 40;
		objectCache = [inDatabase->sharedObjectCache newConnection];
		objectCache.countLimit = objectCacheLimit;
		
		metadataCacheLimit = 0;
		metadataCache = [inDatabase->sharedMetadataCache newConnection];
		metadataCache.countLimit = metadataCacheLimit;
		
		self.autoFlushMemoryLevel = YapDatabaseConnectionFlushMemoryLevelMild;
		
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
		#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
			
			// Disable autocheckpointing.
			// We have a separate dedicated connection that handles checkpointing.
			sqlite3_wal_autocheckpoint(db, 0);
			
		#else
			
			// Configure autocheckpointing.
			// Decrease size of WAL from default 1,000 pages to something more mobile friendly.
			sqlite3_wal_autocheckpoint(db, 100);
			
		#endif
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

- (void)dealloc
{
	YDBLogVerbose(@"Dealloc <YapDatabaseConnection %p: databaseName=%@>",
				  self, [database.databasePath lastPathComponent]);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	if (beginTransactionStatement)
		sqlite3_finalize(beginTransactionStatement);
	
	if (commitTransactionStatement)
		sqlite3_finalize(commitTransactionStatement);
	
	if (yapGetDataForKeyStatement)
		sqlite3_finalize(yapGetDataForKeyStatement);
	
	if (yapSetDataForKeyStatement)
		sqlite3_finalize(yapSetDataForKeyStatement);
	
	if (db)
		sqlite3_close(db);
	
	[database removeConnection:self];
	
#if NEEDS_DISPATCH_RETAIN_RELEASE
	if (connectionQueue)
		dispatch_release(connectionQueue);
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
				objectCache = [database->sharedObjectCache newConnection];
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
				metadataCache = [database->sharedMetadataCache newConnection];
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
	
	if (level >= YapDatabaseConnectionFlushMemoryLevelFull)
	{
		if (yapGetDataForKeyStatement) {
			sqlite3_finalize(yapGetDataForKeyStatement);
			yapGetDataForKeyStatement = NULL;
		}
		if (yapSetDataForKeyStatement) {
			sqlite3_finalize(yapSetDataForKeyStatement);
			yapSetDataForKeyStatement = NULL;
		}
		if (beginTransactionStatement) {
			sqlite3_finalize(beginTransactionStatement);
			beginTransactionStatement = NULL;
		}
		if (commitTransactionStatement) {
			sqlite3_finalize(commitTransactionStatement);
			commitTransactionStatement = NULL;
		}
	}
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
		dispatch_async(connectionQueue, block);
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
	[self flushMemoryWithLevel:[self autoFlushMemoryLevel]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Statements
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (sqlite3_stmt *)beginTransactionStatement
{
	if (beginTransactionStatement == NULL)
	{
		char *stmt = "BEGIN TRANSACTION;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &beginTransactionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'beginTransactionStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return beginTransactionStatement;
}

- (sqlite3_stmt *)commitTransactionStatement
{
	if (commitTransactionStatement == NULL)
	{
		char *stmt = "COMMIT TRANSACTION;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &commitTransactionStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'commitTransactionStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return commitTransactionStatement;
}

- (sqlite3_stmt *)yapGetDataForKeyStatement
{
	if (yapGetDataForKeyStatement == NULL)
	{
		char *stmt = "SELECT \"data\" FROM \"yap\" WHERE \"key\" = ?;";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &yapGetDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'yapGetDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return yapGetDataForKeyStatement;
}

- (sqlite3_stmt *)yapSetDataForKeyStatement
{
	if (yapSetDataForKeyStatement == NULL)
	{
		char *stmt = "INSERT OR REPLACE INTO \"yap\" (\"key\", \"data\") VALUES (?, ?);";
		
		int status = sqlite3_prepare_v2(db, stmt, strlen(stmt)+1, &yapSetDataForKeyStatement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'yapSetDataForKeyStatement': %d %s", status, sqlite3_errmsg(db));
		}
	}
	
	return yapSetDataForKeyStatement;
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
		
		YapAbstractDatabaseTransaction *transaction = [self newReadTransaction];
		
		[self preReadTransaction:transaction];
		
		block(transaction);
		
		[self postReadTransaction:transaction];
	}});
	
	#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
	
	// If needed, execute a passive checkpoint operation on a low-priority background thread.
	[database maybeRunCheckpointInBackground];
	
	#endif
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
	dispatch_sync(database.writeQueue, ^{ @autoreleasepool {
		
		YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
		
		[self preReadWriteTransaction:transaction];
		
		block(transaction);
		
		[self postReadWriteTransaction:transaction];
		
	}}); // End dispatch_sync(database.writeQueue)
	});  // End dispatch_sync(connectionQueue)
	
	#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
	
	// Execute a passive checkpoint operation on a low-priority background thread.
	[database runCheckpointInBackground];
	
	#endif
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
		
		YapAbstractDatabaseTransaction *transaction = [self newReadTransaction];
		
		[self preReadTransaction:transaction];
		
		block(transaction);
		
		[self postReadTransaction:transaction];
		
		if (completionBlock)
			dispatch_async(completionQueue, completionBlock);
		
		#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
		
		// If needed, execute a passive checkpoint operation on a low-priority background thread.
		[database maybeRunCheckpointInBackground];
		
		#endif
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
	dispatch_sync(database.writeQueue, ^{ @autoreleasepool {
		
		YapAbstractDatabaseTransaction *transaction = [self newReadWriteTransaction];
		
		[self preReadWriteTransaction:transaction];
		
		block(transaction);
		
		[self postReadWriteTransaction:transaction];
		
		if (completionBlock)
			dispatch_async(completionQueue, completionBlock);
		
		#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
		
		// Execute a passive checkpoint operation on a low-priority background thread.
		[database runCheckpointInBackground];
		
		#endif
		
	}}); // End dispatch_sync(database.writeQueue)
	});  // End dispatch_async(connectionQueue)
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark States
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapAbstractDatabaseTransaction *)newReadTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

- (YapAbstractDatabaseTransaction *)newReadWriteTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
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
		
	dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
		
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
		// We have an in-memory snapshot of the metadata dictionary.
		// This is kept in-sync with what's in the database.
		// But what happens if the write transaction commits its changes before we perform our select statement?
		// Our select statement would acquire a different snapshot than our in-memory metadata snapshot.
		// Thus, we look to see if there are any write transactions.
		// If there are, then we immediately acquire the "sql-level" shared read lock.
		
		__block BOOL hasActiveWriteTransaction = NO;
		__block YapDatabaseConnectionState *myState = nil;
		
		[database enumerateConnectionStates:^(YapDatabaseConnectionState *state){
			
			if (state.connection == self)
			{
				myState = state;
				myState.yapLevelSharedReadLock = YES;
			}
			else if (state.yapLevelExclusiveWriteLock)
			{
				hasActiveWriteTransaction = YES;
			}
		}];
		
		// Pre-Read-Transaction: Step 3 of 3
		//
		// Update our in-memory data (caches, etc) if needed.
		
		if (hasActiveWriteTransaction)
		{
			// There IS a write transaction in progress.
			// Thus it is not safe to proceed until we acquire a "sql-level" snapshot.
			//
			// Furthermore, we MUST ensure that our "yap-level" snapshot of the in-memory data (caches, etc)
			// is in sync with our "sql-level" snapshot of the database.
			//
			// We can check this by comparing the connection's lastWriteTimestamp ivar with
			// the lastWriteTimestamp read from disk (via sqlite select).
			//
			// If the two match then our snapshots are in sync.
			// If they don't then we need to get caught up by processing changesets.
			
			NSTimeInterval yapLastWriteTimestamp = cacheLastWriteTimestamp;
			NSTimeInterval sqlLastWriteTimestamp = [self selectLastWriteTimestamp];
			
			if (yapLastWriteTimestamp < sqlLastWriteTimestamp)
			{
				// The transaction can see the sqlite commit from another transaction,
				// and it hasn't processed the changeset(s) yet. We need to process them now.
				
				NSArray *changesets = [database pendingAndCommittedChangesSince:yapLastWriteTimestamp
				                                                          until:sqlLastWriteTimestamp];
				
				for (NSDictionary *changeset in changesets)
				{
					[self noteCommittedChanges:changeset];
				}
			}
			
			myState.sqlLevelSharedReadLock = YES;
			hasMarkedSqlLevelSharedReadLock = YES;
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
			
			NSTimeInterval localLastWriteTimestamp = cacheLastWriteTimestamp;
			NSTimeInterval globalLastWriteTimestamp = [database lastWriteTimestamp];
			
			if (localLastWriteTimestamp < globalLastWriteTimestamp)
			{
				// The transaction hasn't processed recent changeset(s) yet. We need to process them now.
				
				NSArray *changesets = [database pendingAndCommittedChangesSince:localLastWriteTimestamp
				                                                          until:globalLastWriteTimestamp];
				
				for (NSDictionary *changeset in changesets)
				{
					[self noteCommittedChanges:changeset];
				}
			}
			
			myState.yapLevelSharedReadLock = YES;
			myState.sqlLevelSharedReadLock = NO;
			hasMarkedSqlLevelSharedReadLock = NO;
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
	// Post-Read-Transaction: Step 1 of 3
	//
	// 1. Execute "COMMIT TRANSACTION" on database connection.
	// If we had acquired "sql-level" shared read lock, this will release associated resources.
	// It may also free the auto-checkpointing architecture within sqlite to sync the WAL to the database.
	
	[transaction commitTransaction];
	
	__block YapDatabaseConnectionState *writeStateToSignal = nil;
	dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
		
		// Post-Read-Transaction: Step 2 of 3
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
		
		__block BOOL wasMaybeBlockingWriteTransaction = NO;
		__block NSUInteger countOtherMaybeBlockingWriteTransaction = 0;
		__block YapDatabaseConnectionState *blockedWriteState = nil;
		
		[database enumerateConnectionStates:^(YapDatabaseConnectionState *state){
			
			if (state.connection == self)
			{
				wasMaybeBlockingWriteTransaction = state.yapLevelSharedReadLock && !state.sqlLevelSharedReadLock;
				state.yapLevelSharedReadLock = NO;
				state.sqlLevelSharedReadLock = NO;
			}
			else if (state.yapLevelSharedReadLock && !state.sqlLevelSharedReadLock)
			{
				countOtherMaybeBlockingWriteTransaction++;
			}
			else if (state.waitingForWriteLock)
			{
				blockedWriteState = state;
			}
		}];
		
		if (wasMaybeBlockingWriteTransaction && countOtherMaybeBlockingWriteTransaction == 0 && blockedWriteState)
		{
			writeStateToSignal = blockedWriteState;
		}
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) completing read-only transaction.", self);
	}});
	
	// Post-Read-Transaction: Step 3 of 3
	//
	// If we discovered a blocked write transaction,
	// and it was blocked waiting on us (because we had a "yap-level" snapshot without an "sql-level" snapshot),
	// and it's no longer blocked on any other read transaction (that have "yap-level" snapshots
	// without "sql-level snapshots"), then signal the write semaphore so the blocked thread wakes up.
	
	if (writeStateToSignal)
	{
		YDBLogVerbose(@"YapDatabaseConnection(%p) signaling blocked write on connection(%p)",
		                                    self, writeStateToSignal.connection);
		
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
	// Pre-Write-Transaction: Step 1 of 3
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
	
	dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
		
		// Pre-Write-Transaction: Step 2 of 3
		//
		// Update our connection state within the state table.
		//
		// We are the only write transaction for this database.
		// It is important for read-only transactions on other connections to know there's a writer.
		
		[database enumerateConnectionStates:^(YapDatabaseConnectionState *state){
	
			if (state.connection == self)
			{
				state.yapLevelExclusiveWriteLock = YES;
			}
		}];
		
		// Pre-Write-Transaction: Step 3 of 3
		//
		// Validate our caches based on lastWriteTimestamp
		
		NSTimeInterval localLastWriteTimestamp = cacheLastWriteTimestamp;
		NSTimeInterval globalLastWriteTimestamp = [database lastWriteTimestamp];
		
		if (localLastWriteTimestamp < globalLastWriteTimestamp)
		{
			NSArray *changesets = [database pendingAndCommittedChangesSince:localLastWriteTimestamp
			                                                          until:globalLastWriteTimestamp];
			
			for (NSDictionary *changeset in changesets)
			{
				[self noteCommittedChanges:changeset];
			}
			
			NSAssert(cacheLastWriteTimestamp == globalLastWriteTimestamp, @"Invalid connection state");
		}
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) starting read-write transaction.", self);
	}});
}

/**
 * This method executes the state transition steps required after executing a read-only transaction block.
 *
 * This method must be invoked from within the connectionQueue.
 * This method must be invoked from within the database.writeQueue.
**/
- (void)postReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	// Post-Write-Transaction: Step 1 of 6
	//
	// Update the lastWriteTimestamp in the 'yap' database (if any changes were made).
	// We use this to check for a race condition.
	
	NSMutableDictionary *changeset = [self changeset];
	if (changeset)
	{
		cacheLastWriteTimestamp = [self updateLastWriteTimestamp];
		
		[changeset setObject:@(cacheLastWriteTimestamp) forKey:@"lastWriteTimestamp"];
	}
	
	// Post-Write-Transaction: Step 2 of 6
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
		
		dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
			
			[database enumerateConnectionStates:^(YapDatabaseConnectionState *state){
				
				if (state.connection == self)
				{
					myState = state;
				}
				else if (state.yapLevelSharedReadLock && !state.sqlLevelSharedReadLock)
				{
					waitForReadOnlyTransactions = YES;
				}
			}];
			
			if (waitForReadOnlyTransactions)
			{
				myState.waitingForWriteLock = YES;
			}
			else
			{
				myState.waitingForWriteLock = NO;
				safeToCommit = YES;
				
				// Post-Write-Transaction: Step 3 of 6
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
				// By registering the pending changeset in advance, we provide a near seamless workaround for the edge case.
				
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
	
	// Post-Write-Transaction: Step 4 of 6
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
	
	dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
		
		// Post-Write-Transaction: Step 5 of 6
		//
		// Notify database of changes, and drop reference to set of changed keys.
		
		if (changeset)
		{
			[database noteCommittedChanges:changeset fromConnection:self];
		}
		
		// Post-Write-Transaction: Step 6 of 6
		//
		// Update our connection state within the state table.
		//
		// We are the only write transaction for this database.
		// It is important for read-only transactions on other connections to know we're no longer a writer.
		
		myState.yapLevelExclusiveWriteLock = NO;
		myState.waitingForWriteLock = NO;
		
		YDBLogVerbose(@"YapDatabaseConnection(%p) completing read-write transaction.", self);
	}});
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
- (NSTimeInterval)selectLastWriteTimestamp
{
	sqlite3_stmt *statement = [self yapGetDataForKeyStatement];
	if (statement == NULL) return 0.0;
	
	NSTimeInterval result = 0.0;
	
	// SELECT data FROM 'yap' WHERE key = ? ;
	
	char *key = "lastWriteTimestamp";
	sqlite3_bind_text(statement, 1, key, strlen(key), SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		if (blobSize >= sizeof(double))
		{
			NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			NSNumber *number = [NSKeyedUnarchiver unarchiveObjectWithData:data];
			
			result = [number doubleValue];
		}
		else
		{
			NSData *data = [[NSData alloc] initWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			
			YDBLogError(@"Error in 'yapGetDataForKeyStatement': Faulty data? %@", data);
		}
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
 * This method updates the 'lastWriteTimestamp' row in the database.
**/
- (NSTimeInterval)updateLastWriteTimestamp
{
	NSTimeInterval newLastWriteTimestamp = [[NSProcessInfo processInfo] systemUptime];
	
	sqlite3_stmt *statement = [self yapSetDataForKeyStatement];
	if (statement == NULL) return newLastWriteTimestamp;
	
	NSNumber *number = [NSNumber numberWithDouble:newLastWriteTimestamp];
	
	// INSERT OR REPLACE INTO "yap" ("key", "data") VALUES (?, ?);
	
	char *key = "lastWriteTimestamp";
	sqlite3_bind_text(statement, 1, key, strlen(key), SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *data = [NSKeyedArchiver archivedDataWithRootObject:number];
	sqlite3_bind_blob(statement, 2, data.bytes, data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return newLastWriteTimestamp;
}

- (void)markSqlLevelSharedReadLockAcquired
{
	NSAssert(hasMarkedSqlLevelSharedReadLock == NO, @"Method called but unneeded. Unnecessary overhead.");
	if (hasMarkedSqlLevelSharedReadLock) return;
	
	__block YapDatabaseConnectionState *writeStateToSignal = nil;
	
	dispatch_sync(database.snapshotQueue, ^{ @autoreleasepool {
		
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
		
		[database enumerateConnectionStates:^(YapDatabaseConnectionState *state){
			
			if (state.connection == self)
			{
				state.sqlLevelSharedReadLock = YES;
			}
			else if (state.yapLevelSharedReadLock && !state.sqlLevelSharedReadLock)
			{
				countOtherMaybeBlockingWriteTransaction++;
			}
			else if (state.waitingForWriteLock)
			{
				blockedWriteState = state;
			}
		}];
		
		if (countOtherMaybeBlockingWriteTransaction == 0 && blockedWriteState)
		{
			writeStateToSignal = blockedWriteState;
		}
	}});
	
	hasMarkedSqlLevelSharedReadLock = YES;
	
	if (writeStateToSignal)
	{
		YDBLogVerbose(@"YapDatabaseConnection(%p) signaling blocked write on connection(%p)",
											 self, writeStateToSignal.connection);
		[writeStateToSignal signalWriteLock];
	}
}

/**
 * REQUIRED OVERRIDE HOOK.
 *
 * This method is invoked from within the postReadWriteTransaction operation.
 * This method is invoked before anything has been committed.
 *
 * If changes have been made, it should return a changeset dictionary.
 * If no changes have been made, it should return nil.
 * 
 * @see [YapAbstractDatabaseConnection noteCommittedChanges:]
 * @see [YapAbstractDatabase cacheChangesetBlockFromChanges:]
**/
- (NSMutableDictionary *)changeset
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

/**
 * Optional override hook.
 * You should likely invoke [super noteCommittedChanges:changeset] if you do.
 *
 * This method is invoked when a sibling connection (a separate connection for the same database)
 * finishes making a change to the database. We take this opportunity to flush from our cache anything that changed.
 * This allows us to keep our cache mostly full, and just discard changed items.
 * 
 * Note: This is an optimization that may occasionally be spoiled due to the multi-threaded nature of connections.
 * For example, if a separate connection in another thread makes a change, then by the time we get this notification,
 * our connection may have already begun a transaction. The atomic snapshot architecture takes over at that point,
 * and will detect the race condition, and fully flush the cache. This method is an optimization that
 * allows us to avoid the full flush a majority of the time.
**/
- (void)noteCommittedChanges:(NSDictionary *)changeset
{
	NSAssert(dispatch_get_specific(IsOnConnectionQueueKey), @"Method must be invoked on connectionQueue");
	
	// Grab the new lastWriteTimestamp.
	// This tells us the minimum lastWriteTimestamp we could get if we started a transaction right now.
	
	NSTimeInterval newCacheLastWriteTimestamp = [[changeset objectForKey:@"lastWriteTimestamp"] doubleValue];
	
	if (newCacheLastWriteTimestamp <= cacheLastWriteTimestamp)
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
		
		return;
	}
	
	// Update the caches.
	// 
	// Each cache will iterate over its local list of keys, and invoke our changeset_block.
	// If our changeset_block returns 0, the cache will continue and leave its cached value for that key unchanged.
	// If our changeset_block returns -1, the cache will delete its cached value for that key.
	// If our changeset_block returns +1, the cache will update its cached value for that key from the shared cache.
	//
	// If a cached value is updated from the shared cache,
	// it will used the cacheLastWriteTimestamp to fetch the proper value.
	//
	// Recall that the shared cache stores multiple values per key, based on timestamp.
	// The timestamps allow concurrency while maintaining the atomic nature of the database transaction.
	// Thus an active readwrite connection can be making changes to the shared cache
	// while a readonly connection continues using the shared cache for its current transaction.
	
	int (^changeset_block)(id key) = [database cacheChangesetBlockFromChanges:changeset];
	
	[objectCache noteCommittedChangesetBlock:changeset_block writeTimestamp:cacheLastWriteTimestamp];
	[metadataCache noteCommittedChangesetBlock:changeset_block writeTimestamp:cacheLastWriteTimestamp];
}

@end
