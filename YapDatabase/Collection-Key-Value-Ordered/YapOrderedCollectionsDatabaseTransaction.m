#import "YapOrderedCollectionsDatabaseTransaction.h"
#import "YapOrderedCollectionsDatabasePrivate.h"

#import "YapCollectionsDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapOrderedCollectionsDatabaseReadTransactionProxy

- (id)initWithConnection:(YapOrderedCollectionsDatabaseConnection *)inConnection
             transaction:(YapCollectionsDatabaseReadTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		connection = inConnection;
		transaction = inTransaction;
	}
	return self;
}

#pragma mark Message Forwarding

/**
 * The YapOrderedDatabaseTransaction classes don't extend the YapDatabaseTransaction classes.
 * Instead they wrap them, and automatically forward unhandled methods.
 *
 * Why the funky architecture?
 * It all has to do with YapOrderedDatabaseReadWriteTransaction.
 * This class actually needs to extend both YapOrderedDatabaseReadTransaction and YapDatabaseReadWriteTransaction.
 **/
- (id)forwardingTargetForSelector:(SEL)aSelector
{
	return transaction;
	
	// Since using forwardingTargetForSelector is slower than normal message invocation,
	// we implement a few of the most common methods to speed things up a wee bit.
}

- (void)beginTransaction
{
	[transaction beginTransaction];
}

- (void)commitTransaction
{
	[transaction commitTransaction];
}

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	return [transaction objectForKey:key inCollection:collection];
}

#pragma mark List

- (NSArray *)orderedKeysInCollection:(NSString *)collection
{
	return [[self orderForCollection:collection] allKeys:self];
}

- (NSUInteger)orderedKeysCountInCollection:(NSString *)collection
{
	return [[self orderForCollection:collection] numberOfKeys];
}

- (NSArray *)keysInRange:(NSRange)range collection:(NSString *)collection
{
	return [[self orderForCollection:collection] keysInRange:range transaction:self];
}

#pragma mark Index

- (NSString *)keyAtIndex:(NSUInteger)index inCollection:(NSString *)collection
{
	return [[self orderForCollection:collection] keyAtIndex:index transaction:self];
}

- (id)objectAtIndex:(NSUInteger)index inCollection:(NSString *)collection
{
	return [transaction objectForKey:[self keyAtIndex:index inCollection:collection] inCollection:collection];
}

- (id)metadataAtIndex:(NSUInteger)index inCollection:(NSString *)collection
{
	return [transaction metadataForKey:[self keyAtIndex:index inCollection:collection] inCollection:collection];
}

#pragma mark Enumerate

- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysUsingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id metadata = [transaction metadataForKey:key inCollection:collection];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                        withOptions:(NSEnumerationOptions)options
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysWithOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id metadata = [transaction metadataForKey:key inCollection:collection];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                              range:(NSRange)range
                                        withOptions:(NSEnumerationOptions)options
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysInRange:range withOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
		
		id metadata = [transaction metadataForKey:key inCollection:collection];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysUsingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
		
		id object, metadata;
		if ([transaction getObject:&object metadata:&metadata forKey:key inCollection:collection])
		{
			block(keyIdx, key, object, metadata, stop);
		}
		else
		{
			YDBLogWarn(@"Missing object for collection(%@) key(%@), but key listed in order!", collection, key);
		}
		
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                       withOptions:(NSEnumerationOptions)options
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysWithOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
		
		id object, metadata;
		if ([transaction getObject:&object metadata:&metadata forKey:key inCollection:collection])
		{
			block(keyIdx, key, object, metadata, stop);
		}
		else
		{
			YDBLogWarn(@"Missing object for collection(%@) key(%@), but key listed in order!", collection, key);
		}
		
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                             range:(NSRange)range
                                       withOptions:(NSEnumerationOptions)options
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	YapDatabaseOrder *order = [self orderForCollection:collection];
	[order enumerateKeysInRange:range withOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id object, metadata;
		if ([transaction getObject:&object metadata:&metadata forKey:key inCollection:collection])
		{
			block(keyIdx, key, object, metadata, stop);
		}
		else
		{
			YDBLogWarn(@"Missing object for collection(%@) key(%@), but key listed in order!", collection, key);
		}
		
	} transaction:self];
}

#pragma mark Order

- (YapDatabaseOrder *)orderForCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	YapDatabaseOrder *order = [connection->orderDict objectForKey:collection];
	if (order == nil)
	{
		order = [[YapDatabaseOrder alloc] initWithUserInfo:collection];
		[connection->orderDict setObject:order forKey:collection];
	}
	
	if (![order isPrepared])
	{
		[order prepare:self];
	}
	
	return order;
}

#pragma mark YapOrderReadTransaction

- (NSData *)dataForKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	if (key == nil) return nil;
	
	NSString *collection = (NSString *)sender.userInfo;
	
	sqlite3_stmt *statement = [connection getOrderDataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "data" FROM "order" WHERE "collection" = ? AND "key" = ? ;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	YapDatabaseString _key;        MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	NSData *result = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getOrderDataForKeyStatement': %d %s, collection(%@) key(%@)",
					status, sqlite3_errmsg(connection->db), collection, key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	return result;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapOrderedCollectionsDatabaseReadWriteTransactionProxy

- (void)commitTransaction
{
	__block NSMutableArray *orderKeysToRemove = nil;
	
	[connection->orderDict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
		
		YapDatabaseOrder *order = (YapDatabaseOrder *)obj;
		
		[order commitTransaction:self];
		
		if ([order hasZeroKeys])
		{
			NSString *collection = (NSString *)key;
			
			if (orderKeysToRemove == nil)
				orderKeysToRemove = [NSMutableArray arrayWithCapacity:1];
			
			[orderKeysToRemove addObject:collection];
		}
	}];
	
	if ([orderKeysToRemove count] > 0)
	{
		[connection->orderDict removeObjectsForKeys:orderKeysToRemove];
	}
	
	[transaction commitTransaction];
}

#pragma mark Forbidden

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[NSException raise:@"MethodNotAvailable"
	            format:@"Method %@ not available as it doesn't include ordering information."
	                   @" Use appendObject or prependObject methods instead.", NSStringFromSelector(_cmd)];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	[NSException raise:@"MethodNotAvailable"
	            format:@"Method %@ not available as it doesn't include ordering information."
	                   @" Use appendObject or prependObject methods instead.", NSStringFromSelector(_cmd)];
}

#pragma mark Add

- (void)appendObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	return [self appendObject:object forKey:key inCollection:collection withMetadata:nil];
}

- (void)appendObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	if (key == nil)
	{
		YDBLogWarn(@"Cannot append object for collection(%@) with nil key.", collection);
		return;
	}
	if (object == nil)
	{
		YDBLogWarn(@"Cannot append nil object for collection(%@) key(%@).", collection, key);
		return;
	}
	
	// Duplicates are allowed, but a warning is helpful for now.
	if ([transaction hasObjectForKey:key inCollection:collection])
	{
		YDBLogWarn(@"Object for collection(%@) key(%@) already listed in order. Appending duplicate key to order...",
		           collection, key);
	}
	
	[transaction setObject:object forKey:key inCollection:collection withMetadata:metadata];
	
	[[self orderForCollection:collection] appendKey:key transaction:self];
}

- (void)prependObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self prependObject:object forKey:key inCollection:collection withMetadata:nil];
}

- (void)prependObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	if (key == nil)
	{
		YDBLogWarn(@"Cannot prepend object for collection(%@) with nil key.", collection);
		return;
	}
	if (object == nil)
	{
		YDBLogWarn(@"Cannot prepend nil object for collection(%@) key(%@).", collection, key);
		return;
	}
	
	// Duplicates are allowed, but a warning is helpful for now.
	if ([transaction hasObjectForKey:key inCollection:collection])
	{
		YDBLogWarn(@"Object for collection(%@) key(%@) already listed in order. Prepending duplicate key to order...",
		           collection, key);
	}
	
	[transaction setObject:object forKey:key inCollection:collection withMetadata:metadata];
	
	[[self orderForCollection:collection] prependKey:key transaction:self];
}

- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self insertObject:object atIndex:index forKey:key inCollection:collection withMetadata:nil];
}

- (void)insertObject:(id)object
             atIndex:(NSUInteger)index
              forKey:(NSString *)key
        inCollection:(NSString *)collection
        withMetadata:(id)metadata
{
	if (key == nil)
	{
		YDBLogWarn(@"Cannot insert object in collection(%@) atIndex(%ud) with nil key.", collection, index);
		return;
	}
	if (object == nil)
	{
		YDBLogWarn(@"Cannot insert nil object for collection(%@) key(%@) atIndex(%ud).", collection, key, index);
		return;
	}
	
	// Duplicates are allowed, but a warning is helpful for now.
	if ([transaction hasObjectForKey:key inCollection:collection])
	{
		YDBLogWarn(@"Object for collection(%@) key(%@) already listed in order. Inserting duplicate key in order...",
		           collection, key);
	}
	
	[transaction setObject:object forKey:key inCollection:collection withMetadata:metadata];
	
	[[self orderForCollection:collection] insertKey:key atIndex:index transaction:self];
}

- (void)updateObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self updateObject:object forKey:key inCollection:collection withMetadata:nil];
}

- (void)updateObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
	}
	else if ([transaction hasObjectForKey:key inCollection:collection]) // In-place update only
	{
		[transaction setObject:object forKey:key inCollection:collection withMetadata:metadata];
	}
}

#pragma mark Remove

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	[transaction removeObjectForKey:key inCollection:collection];
	
	[[self orderForCollection:collection] removeKey:key transaction:self];
}

- (void)removeObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	[transaction removeObjectsForKeys:keys inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
}

- (void)removeAllObjectsInCollection:(NSString *)collection;
{
	[transaction removeAllObjectsInCollection:collection];
	
	[[self orderForCollection:collection] removeAllKeys:self];
}

- (void)removeAllObjectsInAllCollections
{
	[transaction removeAllObjectsInAllCollections];
	
	// First clear the in-memory state of each individual order.
	
	for (YapDatabaseOrder *order in [connection->orderDict objectEnumerator])
	{
		[order removeAllKeys:nil]; // Yes nil is correct. We're going to modify the database manually below.
	}
	
	// Now clear the whole database.
	// Doing it this way is faster than removing each collection one-at-a-time.
	
	sqlite3_stmt *statement = [connection removeAllOrderDataStatement];
	if (statement == NULL) return;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeAllOrderDataStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
}

- (void)removeObjectAtIndex:(NSUInteger)index inCollection:(NSString *)collection
{
	NSString *key = [[self orderForCollection:collection] removeKeyAtIndex:index transaction:self];
	
	[transaction removeObjectForKey:key inCollection:collection];
}

- (void)removeObjectsInRange:(NSRange)range collection:(NSString *)collection
{
	NSArray *keys = [[self orderForCollection:collection] removeKeysInRange:range transaction:self];
	
	[transaction removeObjectsForKeys:keys inCollection:collection];
}

- (NSArray *)removeObjectsEarlierThan:(NSDate *)date inCollection:(NSString *)collection
{
	NSArray *keys = [transaction removeObjectsEarlierThan:date inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
	return keys;
}

- (NSArray *)removeObjectsLaterThan:(NSDate *)date inCollection:(NSString *)collection
{
	NSArray *keys = [transaction removeObjectsLaterThan:date inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
	return keys;
}

- (NSArray *)removeObjectsEarlierThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection
{
	NSArray *keys = [transaction removeObjectsEarlierThanOrEqualTo:date inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
	return keys;
}

- (NSArray *)removeObjectsLaterThanOrEqualTo:(NSDate *)date inCollection:(NSString *)collection
{
	NSArray *keys = [transaction removeObjectsLaterThanOrEqualTo:date inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
	return keys;
}

- (NSArray *)removeObjectsFrom:(NSDate *)startDate to:(NSDate *)endDate inCollection:(NSString *)collection
{
	NSArray *keys = [transaction removeObjectsFrom:startDate to:endDate inCollection:collection];
	
	[[self orderForCollection:collection] removeKeys:keys transaction:self];
	return keys;
}

#pragma mark YapOrderReadWriteTransaction

- (void)setData:(NSData *)data forKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	if (data == nil)
	{
		[self removeDataForKey:key order:sender];
		return;
	}
	
	if (key == nil) return;
	NSString *collection = (NSString *)sender.userInfo;
	
	sqlite3_stmt *statement = [connection setOrderDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "order" ("collection", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	YapDatabaseString _key;        MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	sqlite3_bind_blob(statement, 3, data.bytes, data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'setOrderDataForKeyStatement': %d %s, collection(%@) key(%@)",
		           status, sqlite3_errmsg(connection->db), collection, key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
}

- (void)removeDataForKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	if (key == nil) return;
	NSString *collection = (NSString *)sender.userInfo;
	
	sqlite3_stmt *statement = [connection removeOrderDataForKeyStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "order" WHERE "collection" = ? AND "key" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	YapDatabaseString _key;        MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeOrderDataForKeyStatement': %d %s, collection(%@) key(%@)",
		           status, sqlite3_errmsg(connection->db), collection, key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
}

- (void)removeAllDataForOrder:(YapDatabaseOrder *)sender
{
	NSString *collection = (NSString *)sender.userInfo;
	
	sqlite3_stmt *statement = [connection removeOrderDataForCollectionStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "order" WHERE "collection" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeOrderDataForCollectionStatement': %d %s, collection(%@)",
		           status, sqlite3_errmsg(connection->db), collection);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
}

@end
