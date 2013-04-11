#import <Foundation/Foundation.h>

#import "YapAbstractDatabase.h"
#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"

#import "YapDatabaseConnectionState.h"
#import "YapCache.h"

#import "sqlite3.h"

/**
 * Do we use a dedicated background thread/queue to run checkpoint operations?
 *
 * If YES (1), then auto-checkpoint is disabled on all connections.
 * A dedicated background connection runs checkpoint operations after transactions complete.
 *
 * If NO (0), then auto-checkpoint is enabled on all connections.
 * And the typical auto-checkpoint operations are run during commit operations of read-write transactions.
 *
 * If YES, then write operations will complete faster (but the WAL may grow faster).
 * If NO, then write operations will complete slower (but the WAL stays slim).
 *
 * A large size WAL seems to have some kind of negative performance during app launch.
**/
#define YAP_DATABASE_USE_CHECKPOINT_QUEUE 0

/**
 * Helper method to conditionally invoke sqlite3_finalize on a statement, and then set the ivar to NULL.
**/
NS_INLINE void sqlite_finalize_null(sqlite3_stmt **stmtPtr)
{
	if (*stmtPtr) {
		sqlite3_finalize(*stmtPtr);
		*stmtPtr = NULL;
	}
}


@interface YapAbstractDatabase () {
@private
	
#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
	dispatch_queue_t checkpointQueue;
#endif
	
	NSMutableDictionary *views;
	
	NSMutableArray *changesets;
	uint64_t snapshot;
	
#if YAP_DATABASE_USE_CHECKPOINT_QUEUE
	int walPendingPageCount;
	int32_t walCheckpointSchedule;
#endif
	
@protected
	
	sqlite3 *db;
	
@public
	
	void *IsOnSnapshotQueueKey;       // Only to be used by YapAbstractDatabaseConnection
	
	dispatch_queue_t snapshotQueue;   // Only to be used by YapAbstractDatabaseConnection
	dispatch_queue_t writeQueue;      // Only to be used by YapAbstractDatabaseConnection
	
	NSMutableArray *connectionStates; // Only to be used by YapAbstractDatabaseConnection
}

/**
 * Required override hook.
 * Don't forget to invoke [super createTables].
**/
- (BOOL)createTables;

/**
 * Upgrade mechanism.
**/
- (BOOL)get_user_version:(int *)user_version_ptr;

/**
 * Optional override hook.
 * Don't forget to invoke [super prepare].
 * 
 * This method is run asynchronously on the snapshotQueue.
**/
- (void)prepare;

/**
 * Required override hook.
 * Subclasses must implement this method and return the proper class to use for the cache.
**/
- (Class)cacheKeyClass;

/**
 * Use the addConnection method from within newConnection.
 *
 * And when a connection is deallocated,
 * it should remove itself from the list of connections by calling removeConnection.
**/
- (void)addConnection:(YapAbstractDatabaseConnection *)connection;
- (void)removeConnection:(YapAbstractDatabaseConnection *)connection;

/**
 * This method is only accessible from within the snapshotQueue.
 * 
 * The snapshot represents when the database was last modified by a read-write transaction.
 * This information isn persisted to the 'yap' database, and is separately held in memory.
 * It serves multiple purposes.
 * 
 * First is assists in validation of a connection's cache.
 * When a connection begins a new transaction, it may have items sitting in the cache.
 * However the connection doesn't know if the items are still valid because another connection may have made changes.
 * 
 * The snapshot also assists in correcting for a race condition.
 * It order to minimize blocking we allow read-write transactions to commit outside the context
 * of the snapshotQueue. This is because the commit may be a time consuming operation, and we
 * don't want to block read-only transactions during this period. The race condition occurs if a read-only
 * transactions starts in the midst of a read-write commit, and the read-only transaction gets
 * a "yap-level" snapshot that's out of sync with the "sql-level" snapshot. This is easily correctable if caught.
 * Thus we maintain the snapshot in memory, and fetchable via a select query.
 * One represents the "yap-level" snapshot, and the other represents the "sql-level" snapshot.
 *
 * The snapshot is simply a 64-bit integer.
 * It is reset when the YapDatabase instance is initialized,
 * and incremented by each read-write transaction (if changes are actually made).
**/
- (uint64_t)snapshot;

/**
 * This method is only accessible from within the snapshotQueue.
 * 
 * Prior to starting the sqlite commit, the connection must report its changeset to the database.
 * The database will store the changeset, and provide it to other connections if needed (due to a race condition).
 * 
 * The following MUST be in the dictionary:
 *
 * - snapshot : NSNumber with the changeset's snapshot
**/
- (void)notePendingChanges:(NSDictionary *)changeset fromConnection:(YapAbstractDatabaseConnection *)connection;

/**
 * This method is only accessible from within the snapshotQueue.
 * 
 * This method is used if a transaction finds itself in a race condition.
 * That is, the transaction started before it was able to process changesets from sibling connections.
 * 
 * It should fetch the changesets needed and then process them via [connection noteCommittedChanges:].
**/
- (NSArray *)pendingAndCommittedChangesSince:(uint64_t)connectionSnapshot until:(uint64_t)maxSnapshot;

/**
 * This method is only accessible from within the snapshotQueue.
 * 
 * Upon completion of a readwrite transaction, the connection must report its changeset to the database.
 * The database will then forward the changeset to all other connections.
 * 
 * The following MUST be in the dictionary:
 * 
 * - snapshot : NSNumber with the changeset's snapshot
**/
- (void)noteCommittedChanges:(NSDictionary *)changeset fromConnection:(YapAbstractDatabaseConnection *)connection;

#if YAP_DATABASE_USE_CHECKPOINT_QUEUE

/**
 * All checkpointing is done on a low-priority background thread.
 * We checkpoint continuously to keep the WAL-index small.
**/
- (void)maybeRunCheckpointInBackground;
- (void)runCheckpointInBackground;

/**
 * Primarily for debugging.
**/
- (void)syncCheckpoint;

#endif

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseConnection () {
@private
	sqlite3_stmt *beginTransactionStatement;
	sqlite3_stmt *commitTransactionStatement;
	sqlite3_stmt *rollbackTransactionStatement;
	
	sqlite3_stmt *yapGetDataForKeyStatement; // Against "yap" database, for internal use
	sqlite3_stmt *yapSetDataForKeyStatement; // Against "yap" database, for internal use
	
@protected
	dispatch_queue_t connectionQueue;
	void *IsOnConnectionQueueKey;
	
	YapAbstractDatabase *database;
	
	NSMutableDictionary *views;
	
@public
	sqlite3 *db;
	
	uint64_t cacheSnapshot;
	BOOL rollback;
	
	YapCache *objectCache;
	YapCache *metadataCache;
	
	NSUInteger objectCacheLimit;          // Read-only by transaction. Use as consideration of whether to add to cache.
	NSUInteger metadataCacheLimit;        // Read-only by transaction. Use as consideration of whether to add to cache.
	
	BOOL hasMarkedSqlLevelSharedReadLock; // Read-only by transaction. Use as consideration of whether to invoke method.
}

- (id)initWithDatabase:(YapAbstractDatabase *)database;

@property (nonatomic, readonly) dispatch_queue_t connectionQueue;

- (sqlite3_stmt *)beginTransactionStatement;
- (sqlite3_stmt *)commitTransactionStatement;
- (sqlite3_stmt *)rollbackTransactionStatement;

- (void)_flushMemoryWithLevel:(int)level;

- (void)_readWithBlock:(void (^)(id))block;
- (void)_readWriteWithBlock:(void (^)(id))block;

- (void)_asyncReadWithBlock:(void (^)(id))block
            completionBlock:(dispatch_block_t)completionBlock
            completionQueue:(dispatch_queue_t)completionQueue;

- (void)_asyncReadWriteWithBlock:(void (^)(id))block
                 completionBlock:(dispatch_block_t)completionBlock
                 completionQueue:(dispatch_queue_t)completionQueue;

- (YapAbstractDatabaseTransaction *)newReadTransaction;
- (YapAbstractDatabaseTransaction *)newReadWriteTransaction;

- (void)preReadTransaction:(YapAbstractDatabaseTransaction *)transaction;
- (void)postReadTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (void)preReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction;
- (void)postReadWriteTransaction:(YapAbstractDatabaseTransaction *)transaction;

- (void)markSqlLevelSharedReadLockAcquired;

- (void)postRollbackCleanup;

- (NSMutableDictionary *)changeset;
- (void)processChangeset:(NSDictionary *)changeset;

- (void)noteCommittedChanges:(NSDictionary *)changeset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseTransaction () {
@protected
	NSMutableDictionary *views;
	
@public
	__unsafe_unretained YapAbstractDatabaseConnection *abstractConnection;
	
	BOOL isReadWriteTransaction;
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)connection isReadWriteTransaction:(BOOL)flag;

- (void)beginTransaction;
- (void)commitTransaction;
- (void)rollbackTransaction;

@end
