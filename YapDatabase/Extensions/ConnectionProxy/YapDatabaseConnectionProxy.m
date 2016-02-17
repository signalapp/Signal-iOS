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
	void *IsOnQueueKey;
	
	/**
	 * pendingObjectCache & pendingMetadataCache:
	 * 
	 *   These are the values that are waiting to be written to disk.
	 *   This includes values that are currently in the process of being written (in a current read-write transaction),
	 *   as well as those that will be included in the next batch.
	 * 
	 * currentObjectBatch & currentMetadataBatch:
	 * 
	 *   These are the keys that should be included in the next batch.
	 * 
	 * Important:
	 * 
	 *   A user may change a value mulitple times.
	 *   So the value for collection/key might be in the process of being written to disk,
	 *   only to have the user change it again.
	 *   Which means its value in the pendingObjectCache changes,
	 *   and when the read-write transaction completes, it should NOT remove the new value from pendingObjectCache.
	 *   This is why we have BOTH pendingObjectCache && currentObjectBatch.
	**/
	
	NSMutableDictionary<YapCollectionKey *, id> *pendingObjectCache;
	NSMutableDictionary<YapCollectionKey *, id> *pendingMetadataCache;
	
	NSMutableSet<YapCollectionKey *> *currentObjectBatch;
	NSMutableSet<YapCollectionKey *> *currentMetadataBatch;
	
	NSMutableArray<NSMutableSet *> *pendingObjectBatches;
	NSMutableArray<NSMutableSet *> *pendingMetadataBatches;
	NSMutableArray<NSNumber *> *pendingBatchCommits;
	
	uint64_t abortAndResetCount;
	YapWhitelistBlacklist *fetchedCollectionsFilter;
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
		
		IsOnQueueKey = &IsOnQueueKey;
		dispatch_queue_set_specific(queue, IsOnQueueKey, IsOnQueueKey, NULL);
		
		pendingObjectCache   = [[NSMutableDictionary alloc] init];
		pendingMetadataCache = [[NSMutableDictionary alloc] init];
		
		currentObjectBatch   = [[NSMutableSet alloc] init];
		currentMetadataBatch = [[NSMutableSet alloc] init];
		
		pendingObjectBatches   = [[NSMutableArray alloc] initWithCapacity:4];
		pendingMetadataBatches = [[NSMutableArray alloc] initWithCapacity:4];
		pendingBatchCommits    = [[NSMutableArray alloc] initWithCapacity:4];
		
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
	}
	return self;
}

- (void)dealloc
{
	YDBLogAutoTrace();
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Batch Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)queueBatchForCommit:(uint64_t)commit
                withObjects:(NSMutableDictionary **)objectBatchPtr
                   metadata:(NSMutableDictionary **)metadataBatchPtr
{
	YDBLogTrace(@"%@ %llu", THIS_METHOD, commit);
	
	__block NSMutableDictionary *objectBatch = nil;
	__block NSMutableDictionary *metadataBatch = nil;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if (abortAndResetCount > 0) // user asked to abort this write
		{
			abortAndResetCount--;
			return;
		}
		
		NSUInteger oCount = currentObjectBatch.count;
		NSUInteger mCount = currentMetadataBatch.count;
		
		if (oCount == 0 && mCount == 0) // nothing to write
		{
			return; // from block
		}
		
		objectBatch   = [[NSMutableDictionary alloc] initWithCapacity:oCount];
		metadataBatch = [[NSMutableDictionary alloc] initWithCapacity:mCount];
		
		for (YapCollectionKey *ck in currentObjectBatch)
		{
			objectBatch[ck] = pendingObjectCache[ck];
		}
		for (YapCollectionKey *ck in currentMetadataBatch)
		{
			metadataBatch[ck] = pendingMetadataCache[ck];
		}
		
		for (NSMutableSet *prevObjectBatch in pendingObjectBatches)
		{
			[prevObjectBatch minusSet:currentObjectBatch];
		}
		for (NSMutableSet *prevMetadataBatch in pendingMetadataBatches)
		{
			[prevMetadataBatch minusSet:currentMetadataBatch];
		}
		
		[pendingObjectBatches addObject:currentObjectBatch];
		[pendingMetadataBatches addObject:currentMetadataBatch];
		[pendingBatchCommits addObject:@(commit)];
		
		currentObjectBatch   = [[NSMutableSet alloc] init];
		currentMetadataBatch = [[NSMutableSet alloc] init];
	}});
	
	if (objectBatchPtr) *objectBatchPtr = objectBatch;
	if (metadataBatchPtr) *metadataBatchPtr = metadataBatch;
}

- (void)dequeueBatchForCommit:(uint64_t)commit
{
	YDBLogTrace(@"%@ %llu", THIS_METHOD, commit);
	
	dispatch_block_t block = ^{ @autoreleasepool {
		
		NSNumber *nextCommit = [pendingBatchCommits firstObject];
		if (!nextCommit || (nextCommit.unsignedLongLongValue != commit))
		{
			// This is not the commit we're looking for
			return;
		}
		
		for (YapCollectionKey *ck in [pendingObjectBatches firstObject])
		{
			if (![currentObjectBatch containsObject:ck])
			{
				[pendingObjectCache removeObjectForKey:ck];
			}
		}
		for (YapCollectionKey *ck in [pendingMetadataBatches firstObject])
		{
			if (![currentMetadataBatch containsObject:ck])
			{
				[pendingMetadataCache removeObjectForKey:ck];
			}
		}
		
		[pendingObjectBatches removeObjectAtIndex:0];
		[pendingMetadataBatches removeObjectAtIndex:0];
		[pendingBatchCommits removeObjectAtIndex:0];
	}};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_async(queue, block);
}

- (void)asyncWriteNextBatch
{
	YDBLogAutoTrace();
	
	__block uint64_t commit = 0;
	__weak YapDatabaseConnectionProxy *weakSelf = self;
	
	#pragma clang diagnostic push
	#pragma clang diagnostic warning "-Wimplicit-retain-self"
	[readWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		__strong YapDatabaseConnectionProxy *strongSelf = weakSelf;
		if (strongSelf == nil) return;
		
		commit = transaction.connection.snapshot + 1;
		
		NSMutableDictionary *objectBatch = nil;
		NSMutableDictionary *metadataBatch = nil;
		[strongSelf queueBatchForCommit:commit withObjects:&objectBatch metadata:&metadataBatch];
		
		YapNull *yapnull = [YapNull null];
		
		[objectBatch enumerateKeysAndObjectsUsingBlock:^(YapCollectionKey *ck, id object, BOOL *stop) {
			
			if (object == yapnull)
			{
				[transaction removeObjectForKey:ck.key inCollection:ck.collection];
			}
			else
			{
				id metadata = metadataBatch[ck];
				if (metadata == yapnull) {
					[transaction setObject:object forKey:ck.key inCollection:ck.collection withMetadata:nil];
				}
				else if (metadata) {
					[transaction setObject:object forKey:ck.key inCollection:ck.collection withMetadata:metadata];
				}
				else {
					[transaction replaceObject:object forKey:ck.key inCollection:ck.collection];
				}
			}
			
			[metadataBatch removeObjectForKey:ck];
		}];
		
		[metadataBatch enumerateKeysAndObjectsUsingBlock:^(YapCollectionKey *ck, id metadata, BOOL *stop) {
			
			if (metadata == yapnull) {
				[transaction replaceMetadata:nil forKey:ck.key inCollection:ck.collection];
			}
			else {
				[transaction replaceMetadata:metadata forKey:ck.key inCollection:ck.collection];
			}
		}];
		
	} completionQueue:queue completionBlock:^{
		
		__strong YapDatabaseConnectionProxy *strongSelf = weakSelf;
		if (strongSelf)
		{
			[strongSelf dequeueBatchForCommit:commit];
		}
	}];
	#pragma clang diagnostic pop
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the proxy's value for the given collection/key tuple.
 *
 * If this proxy instance has recently had a value set for the given collection/key,
 * then that value is returned, even if the value has not been written to the database yet.
**/
- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @""; // required for [filter isAllowed:collection]
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block id object = nil;
	__block BOOL collectionFiltered = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		object = [pendingObjectCache objectForKey:ck];
		
		if (!object && fetchedCollectionsFilter) {
			collectionFiltered = ![fetchedCollectionsFilter isAllowed:collection];
		}
	}});
	
	if (object)
	{
		if (object == [YapNull null])
			return nil;
		else
			return object;
	}
	
	if (!collectionFiltered)
	{
		[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			object = [transaction objectForKey:key inCollection:collection];
		}];
	}
	
	return object;
}

/**
 * Returns the proxy's value for the given collection/key tuple.
 *
 * If this proxy instance has recently had a value set for the given collection/key,
 * then that value is returned, even if the value has not been written to the database yet.
**/
- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @""; // required for [filter isAllowed:collection]
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block id metadata = nil;
	__block BOOL collectionFiltered = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		metadata = [pendingMetadataCache objectForKey:ck];
		
		if (!metadata && fetchedCollectionsFilter) {
			collectionFiltered = ![fetchedCollectionsFilter isAllowed:collection];
		}
	}});
	
	if (metadata)
	{
		if (metadata == [YapNull null])
			return nil;
		else
			return metadata;
	}
	
	if (!collectionFiltered)
	{
		[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			metadata = [transaction metadataForKey:key inCollection:collection];
		}];
	}
	
	return metadata;
}

/**
 * Returns the proxy's value for the given collection/key tuple.
 *
 * If this proxy instance has recently had a value set for the given collection/key,
 * then that value is returned, even if the value has not been written to the database yet.
**/
- (BOOL)getObject:(id *)objectPtr
         metadata:(id *)metadataPtr
           forKey:(NSString *)key
     inCollection:(nullable NSString *)collection
{
	if (key == nil)
	{
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	if (collection == nil) collection = @""; // required for [filter isAllowed:collection]
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block id object = nil;
	__block id metadata = nil;
	__block BOOL collectionFiltered = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		object = [pendingObjectCache objectForKey:ck];
		metadata = [pendingMetadataCache objectForKey:ck];
		
		if ((!object || !metadata) && fetchedCollectionsFilter) {
			collectionFiltered = ![fetchedCollectionsFilter isAllowed:collection];
		}
	}});
	
	if (object && metadata)
	{
		if (objectPtr)   *objectPtr   = ((object   == [YapNull null]) ? nil : object);
		if (metadataPtr) *metadataPtr = ((metadata == [YapNull null]) ? nil : metadata);
		return YES;
	}
	
	if (!collectionFiltered)
	{
		[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			if (!object)
			{
				if (!metadata)
					[transaction getObject:&object metadata:&metadata forKey:key inCollection:collection];
				else
					object = [transaction objectForKey:key inCollection:collection];
			}
			else // if (!metadata)
			{
				metadata = [transaction metadataForKey:key inCollection:collection];
			}
		}];
	}
	
	if (objectPtr)   *objectPtr   = ((object   == [YapNull null]) ? nil : object);
	if (metadataPtr) *metadataPtr = ((metadata == [YapNull null]) ? nil : metadata);
	
	return (object != nil);
}

/**
 * Sets a value for the given collection/key tuple.
 *
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
 *
 * @param object
 *   The value for the collection/key tuple.
 *   If nil, this is equivalent to invoking removeObjectForKey:inCollection:
**/
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self setObject:object forKey:key inCollection:collection withMetadata:nil];
}

/**
 * Sets a value for the given collection/key tuple.
 *
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
 *
 * @param object
 *   The value for the collection/key tuple.
 *   If nil, this is equivalent to invoking removeObjectForKey:inCollection:
**/
- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
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
		
		needsWrite = ((currentObjectBatch.count == 0) && (currentMetadataBatch.count == 0));
		
		[pendingObjectCache setObject:object forKey:ck];
		[currentObjectBatch addObject:ck];
		
		if (metadata)
			[pendingMetadataCache setObject:metadata forKey:ck];
		else
			[pendingMetadataCache setObject:[YapNull null] forKey:ck];
		[currentMetadataBatch addObject:ck];
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

/**
 * The replace methods allows you to modify the object, without modifying the metadata for the row.
 * Or vice-versa, you can modify the metadata, without modifying the object for the row.
 *
 * If there is no row in the database for the given key/collection then this method does nothing.
 *
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)replaceObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
		return;
	}
	
	if (key == nil) return;
	
	__block BOOL collectionFiltered = NO;
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if (fetchedCollectionsFilter) {
			collectionFiltered = ![fetchedCollectionsFilter isAllowed:collection];
		}
	}});
	
	__block BOOL existsInDatabase = NO;
	if (!collectionFiltered)
	{
		[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			existsInDatabase = [transaction hasObjectForKey:key inCollection:collection];
		}];
	}
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		id existing_object = [pendingObjectCache objectForKey:ck];
		
		BOOL exists = NO;
		if (existing_object)
		{
			if (existing_object == [YapNull null]) {
				// Ignore - The row doesn't exist to us because it's already scheduled for deletion.
			}
			else {
				exists = YES;
			}
		}
		else if (existsInDatabase)
		{
			exists = YES;
		}
		
		if (exists)
		{
			needsWrite = ((currentObjectBatch.count == 0) && (currentMetadataBatch.count == 0));
			
			[pendingObjectCache setObject:object forKey:ck];
			[currentObjectBatch addObject:ck];
		}
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

/**
 * The replace methods allows you to modify the object, without modifying the metadata for the row.
 * Or vice-versa, you can modify the metadata, without modifying the object for the row.
 *
 * If there is no row in the database for the given key/collection then this method does nothing.
 *
 * The proxy will attempt to write the value to the database at some point in the near future.
 * If the application is terminated before the write completes, then the value may not make it to the database.
 * However, the proxy will immediately begin to return the new value when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)replaceMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return;
	
	__block BOOL collectionFiltered = NO;
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if (fetchedCollectionsFilter) {
			collectionFiltered = ![fetchedCollectionsFilter isAllowed:collection];
		}
	}});
	
	__block BOOL existsInDatabase = NO;
	if (!collectionFiltered)
	{
		[readOnlyConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			existsInDatabase = [transaction hasObjectForKey:key inCollection:collection];
		}];
	}
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		// Check pendingObjectCache (NOT pendingMetadataCache) to determine row status.
		
		id existing_object = [pendingObjectCache objectForKey:ck];
		
		BOOL exists = NO;
		if (existing_object)
		{
			if (existing_object == [YapNull null]) {
				// Ignore - The row doesn't exist to us because it's already scheduled for deletion.
			}
			else {
				exists = YES;
			}
		}
		else if (existsInDatabase)
		{
			exists = YES;
		}
		
		if (exists)
		{
			needsWrite = ((currentObjectBatch.count == 0) && (currentMetadataBatch.count == 0));
			
			if (metadata)
				[pendingMetadataCache setObject:metadata forKey:ck];
			else
				[pendingMetadataCache setObject:[YapNull null] forKey:ck];
			[currentMetadataBatch addObject:ck];
		}
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

/**
 * Removes any set value for the given collection/key tuple.
 *
 * The proxy will attempt to remove the value from the database at some point in the near future.
 * If the application is terminated before the write completes, then the update may not make it to the database.
 * However, the proxy will immediately begin to return nil when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return;
	
	YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		needsWrite = ((currentObjectBatch.count == 0) && (currentMetadataBatch.count == 0));
		
		[pendingObjectCache setObject:[YapNull null] forKey:ck];
		[currentObjectBatch addObject:ck];
		
		[pendingMetadataCache setObject:[YapNull null] forKey:ck];
		[currentMetadataBatch addObject:ck];
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

/**
 * Removes any set value(s) for the given collection/key tuple(s).
 *
 * The proxy will attempt to remove the value(s) from the database at some point in the near future.
 * If the application is terminated before the write completes, then the update may not make it to the database.
 * However, the proxy will immediately begin to return nil when queried for the same collection/key tuple.
 *
 * This is the trade-off you make when using a proxy.
 * The values written to a proxy are not guaranteed to be written to the database.
 * However, the values are immediately available (from this proxy instance) without waiting for the database disk IO.
**/
- (void)removeObjectsForKeys:(NSArray<NSString *> *)keys inCollection:(NSString *)collection
{
	if (keys.count == 0) return;
	
	__block BOOL needsWrite = NO;
	
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		needsWrite = ((currentObjectBatch.count == 0) && (currentMetadataBatch.count == 0));
		
		for (NSString *key in keys)
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
			[pendingObjectCache setObject:[YapNull null] forKey:ck];
			[currentObjectBatch addObject:ck];
			
			[pendingMetadataCache setObject:[YapNull null] forKey:ck];
			[currentMetadataBatch addObject:ck];
		}
	}});
	
	if (needsWrite) {
		[self asyncWriteNextBatch];
	}
}

/**
 * Immediately discards all changes that were queued to written to the database.
 * Thus the changes are not written to the database,
 * and any currently queued readWriteTransaction is aborted.
 *
 * This method is typically used if you intend to clear the database.
 * E.g.:
 *
 * [connectionProxy abortAndReset];
 * [connectionProxy.readWriteTransaction readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *
 *     [transaction removeAllObjectsInAllCollections];
 * }];
**/
- (void)abortAndReset:(YapWhitelistBlacklist *)filter
{
	dispatch_sync(queue, ^{ @autoreleasepool {
		
		if ((currentObjectBatch.count > 0) && (currentMetadataBatch.count > 0))
		{
			abortAndResetCount++;
		}
		fetchedCollectionsFilter = filter;
		
		[pendingObjectCache removeAllObjects];
		[currentObjectBatch removeAllObjects];
		
		[pendingMetadataCache removeAllObjects];
		[currentMetadataBatch removeAllObjects];
	}});
}

/**
 * The fetchedCollectionsFilter is useful when you need to delete one or more collections from the database.
 * For example:
 * - you're going to ASYNCHRONOUSLY delete the "foobar" collection from the database
 * - you want to instruct the connectionProxy to act as if it's readOnlyConnection doesn't see
 *   any objects in this collection (even before the ASYNC cleanup transaction completes).
 * - when the cleanup transaction does complete, you instruct the connectionProxy to return to normal.
 *
 * NSSet *set = [NSSet setWithObject:@"foobar"];
 * YapWhitelistBlacklist *blacklist = [[YapWhitelistBlacklist alloc] initWithBlacklist:set];
 * connectionProxy.fetchedCollectionsFilter = blacklist;
 *
 * [connectionProxy.readWriteTransaction asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *
 *     [transaction removeAllObjectsInCollection:@"foobar"];
 *
 * } completionBlock:^{
 *
 *     // allow the connectionProxy to start reading the "foobar" collection again
 *     connectionProxy.fetchedCollectionsFilter = nil;
 * }];
 *
 * Keep in mind that the fetchedCollectionsFilter only applies to how the proxy interacts with the readOnlyConnection.
 * That is, it still allows the proxy to write values to any collection.
**/
- (YapWhitelistBlacklist *)fetchedCollectionsFilter
{
	__block YapWhitelistBlacklist *filter = nil;
	
	dispatch_block_t block = ^{
		filter = fetchedCollectionsFilter;
	};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
	
	return filter;
}

- (void)setFetchedCollectionsFilter:(YapWhitelistBlacklist *)filter
{
	dispatch_block_t block = ^{
		fetchedCollectionsFilter = filter;
	};
	
	if (dispatch_get_specific(IsOnQueueKey))
		block();
	else
		dispatch_sync(queue, block);
}

@end
