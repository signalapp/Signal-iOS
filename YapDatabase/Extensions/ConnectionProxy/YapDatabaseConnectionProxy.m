#import "YapDatabaseConnectionProxy.h"
#import "YapDatabaseLogging.h"
#import "YapCollectionKey.h"
#import "YapNull.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseConnectionProxy
{
	dispatch_queue_t queue;
	
	NSMutableDictionary<YapCollectionKey *, id> *pendingCache;
	
	NSMutableArray<NSMutableSet *> *pendingBatches;
	NSMutableArray<NSNumber *> *pendingBatchCommits;
	
	NSMutableSet<YapCollectionKey *> *currentBatch;
}

@synthesize readOnlyConnection = readOnlyConnection;
@synthesize readWriteConnection = readWriteConnection;


- (instancetype)initWithDatabase:(YapDatabase *)database
{
	return [self initWithDatabase:database readOnlyConnection:nil readWriteConnection:nil];
}

- (instancetype)initWithDatabase:(YapDatabase *)inDatabase
              readOnlyConnection:(nullable YapDatabaseConnection *)inReadOnlyConnection
             readWriteConnection:(nullable YapDatabaseConnection *)inReadWriteConnection
{
	if (!inReadOnlyConnection && !inReadWriteConnection)
		NSParameterAssert(inDatabase != nil);
	
	if (inReadOnlyConnection && inDatabase)
		NSParameterAssert(inReadOnlyConnection.database == inDatabase);
	
	if (inReadWriteConnection && inDatabase)
		NSParameterAssert(inReadWriteConnection.database == inDatabase);
	
	if (inReadOnlyConnection && inReadWriteConnection)
		NSParameterAssert(inReadOnlyConnection.database == inReadWriteConnection.database);
	
	YapDatabase *database = inDatabase;
	if (database == nil)
		database = inReadOnlyConnection.database;
	if (database == nil)
		database = inReadWriteConnection.database;
	
	if ((self = [super init]))
	{
		queue = dispatch_queue_create("YapDatabaseConnectionProxy", DISPATCH_QUEUE_SERIAL);
		
		pendingCache = [[NSMutableDictionary alloc] init];
		
		pendingBatches      = [[NSMutableArray alloc] initWithCapacity:4];
		pendingBatchCommits = [[NSMutableArray alloc] initWithCapacity:4];
		
		currentBatch = [[NSMutableSet alloc] init];
		
		if (inReadOnlyConnection)
		{
			readOnlyConnection = inReadOnlyConnection;
		}
		else
		{
			readOnlyConnection = [database newConnection];
		#if YapDatabaseEnforcePermittedTransactions
			readOnlyConnection.permittedTransactions = YDB_AnyReadTransaction;
		#endif
		}
		
		if (inReadWriteConnection)
		{
			readWriteConnection = inReadWriteConnection;
		}
		else
		{
			readWriteConnection = [database newConnection];
		#if YapDatabaseEnforcePermittedTransactions
			readWriteConnection.permittedTransactions = YDB_AnyReadWriteTransaction;
		#endif
		}
		
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(databaseModified:)
		                                             name:YapDatabaseModifiedNotification
		                                           object:database];
	}
	return self;
}

- (void)dealloc
{
	YDBLogAutoTrace();
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)databaseModified:(NSNotification *)notification
{
	uint64_t commit = [[notification.userInfo objectForKey:YapDatabaseSnapshotKey] unsignedLongLongValue];
	
	[self asyncDequeueBatchForCommit:commit];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Batch Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)queueBatchForCommit:(uint64_t)commit
{
	YDBLogTrace(@"%@ %llu", THIS_METHOD, commit);
	
	__block NSMutableDictionary *batch = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		NSUInteger pendingCount = currentBatch.count;
		if (pendingCount == 0) {
			return; // from block
		}
		
		batch = [[NSMutableDictionary alloc] initWithCapacity:pendingCount];
		
		for (YapCollectionKey *ck in currentBatch)
		{
			id value = pendingCache[ck];
			if (value) {
				batch[ck] = value;
			}
		}
		
		for (NSMutableSet *prevBatch in pendingBatches)
		{
			[prevBatch minusSet:currentBatch];
		}
		
		[pendingBatches addObject:currentBatch];
		[pendingBatchCommits addObject:@(commit)];
		
		currentBatch = [[NSMutableSet alloc] init];
	}});
	
	return batch;
}

- (void)asyncDequeueBatchForCommit:(uint64_t)commit
{
	YDBLogTrace(@"%@ %llu", THIS_METHOD, commit);
	
	dispatch_async(queue, ^{ @autoreleasepool {
		
		NSNumber *nextCommit = [pendingBatchCommits firstObject];
		if (!nextCommit || (nextCommit.unsignedLongLongValue != commit))
		{
			// This is not the commit we're looking for
			return;
		}
		
		NSSet *batch = [pendingBatches firstObject];
		
		for (YapCollectionKey *ck in batch)
		{
			if (![currentBatch containsObject:ck])
			{
				[pendingCache removeObjectForKey:ck];
			}
		}
		
		[pendingBatches removeObjectAtIndex:0];
		[pendingBatchCommits removeObjectAtIndex:0];
	}});
}

- (void)asyncWriteNextBatch
{
	YDBLogAutoTrace();
	
	[readWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		uint64_t commit = transaction.connection.snapshot + 1;
		
		NSDictionary *batch = [self queueBatchForCommit:commit];
		YapNull *yapnull = [YapNull null];
		
		[batch enumerateKeysAndObjectsUsingBlock:^(YapCollectionKey *ck, id value, BOOL *stop) {
			
			if (value == yapnull) {
				[transaction removeObjectForKey:ck.key inCollection:ck.collection];
			}
			else {
				[transaction setObject:value forKey:ck.key inCollection:ck.collection];
			}
		}];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block id object = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		object = [pendingCache objectForKey:ck];
	}});
	
	if (object)
	{
		if (object == [YapNull null])
			return nil;
		else
			return object;
	}
	
	[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		object = [transaction objectForKey:key inCollection:collection];
	}];
	
	return object;
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
		return;
	}
	
	if (key == nil) return;
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		needsWrite = (currentBatch.count == 0);
		
		[pendingCache setObject:object forKey:ck];
		[currentBatch addObject:ck];
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return;
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		needsWrite = (currentBatch.count == 0);
		
		[pendingCache setObject:[YapNull null] forKey:ck];
		[currentBatch addObject:ck];
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

- (void)removeObjectsForKeys:(NSArray<NSString *> *)keys inCollection:(NSString *)collection
{
	if (keys.count == 0) return;
	
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		needsWrite = (currentBatch.count == 0);
		
		for (NSString *key in keys)
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			[pendingCache setObject:[YapNull null] forKey:ck];
			[currentBatch addObject:ck];
		}
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

@end
