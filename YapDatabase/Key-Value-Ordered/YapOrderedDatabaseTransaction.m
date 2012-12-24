#import "YapOrderedDatabaseTransaction.h"
#import "YapOrderedDatabasePrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapOrderedDatabaseReadTransactionProxy

- (id)initWithConnection:(YapOrderedDatabaseConnection *)inConnection
             transaction:(YapDatabaseReadTransaction *)inTransaction
{
	if ((self = [super init]))
	{
		connection = inConnection;
		transaction = inTransaction;
	}
	return self;
}

#pragma mark List

- (NSArray *)allKeys
{
	// This method is overriden because we need to return the list in the proper order.
	
	return [connection->order allKeys:self];
}

- (NSArray *)keysInRange:(NSRange)range
{
	return [connection->order keysInRange:range transaction:self];
}

#pragma mark Index

- (NSString *)keyAtIndex:(NSUInteger)index
{
	return [connection->order keyAtIndex:index transaction:self];
}

- (id)objectAtIndex:(NSUInteger)index
{
	return [transaction objectForKey:[self keyAtIndex:index]];
}

- (id)metadataAtIndex:(NSUInteger)index
{
	return [transaction metadataForKey:[self keyAtIndex:index]];
}

#pragma mark Enumerate

- (void)enumerateKeysAndMetadataOrderedUsingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	[connection->order enumerateKeysUsingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
		
		id metadata = [transaction metadataForKey:key];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndMetadataOrderedWithOptions:(NSEnumerationOptions)options usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = connection->order;
	[order enumerateKeysWithOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id metadata = [transaction metadataForKey:key];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndMetadataOrderedInRange:(NSRange)range
                                  withOptions:(NSEnumerationOptions)options usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = connection->order;
	[order enumerateKeysInRange:range withOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id metadata = [transaction metadataForKey:key];
		block(keyIdx, key, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedUsingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = connection->order;
	[order enumerateKeysUsingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id object, metadata;
		[transaction getObject:&object metadata:&metadata forKey:key];
		
		block(keyIdx, key, object, metadata, stop);
	
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedWithOptions:(NSEnumerationOptions)options usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = connection->order;
	[order enumerateKeysWithOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
		
		id object, metadata;
		[transaction getObject:&object metadata:&metadata forKey:key];
		
		block(keyIdx, key, object, metadata, stop);
		
	} transaction:self];
}

- (void)enumerateKeysAndObjectsOrderedInRange:(NSRange)range
                                  withOptions:(NSEnumerationOptions)options usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	
	YapDatabaseOrder *order = connection->order;
	[order enumerateKeysInRange:range withOptions:options usingBlock:^(NSUInteger keyIdx, NSString *key, BOOL *stop){
	
		id object, metadata;
		[transaction getObject:&object metadata:&metadata forKey:key];
		
		block(keyIdx, key, object, metadata, stop);
		
	} transaction:self];
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
}

#pragma mark YapOrderReadTransaction Protocol

- (NSData *)dataForKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	if (key == nil) return nil;
	
	sqlite3_stmt *statement = [connection getOrderDataForKeyStatement];
	if (statement == NULL) {
		return nil;
	}
	
	// SELECT "data" FROM "order" WHERE "key" = ? ;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	NSData *result = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'getOrderDataForKeyStatement': %d %s, key(%@)",
		           status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	return result;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapOrderedDatabaseReadWriteTransactionProxy

- (void)commitTransaction
{
	[connection->order commitTransaction:self];
	[transaction commitTransaction];
}

#pragma mark Forbidden

- (void)setObject:(id)object forKey:(NSString *)key
{
	[NSException raise:@"MethodNotAvailable"
	            format:@"Method %@ not available as it doesn't include ordering information."
	                   @" Use appendObject or prependObject methods instead.", NSStringFromSelector(_cmd)];
}

- (void)setObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	[NSException raise:@"MethodNotAvailable"
	            format:@"Method %@ not available as it doesn't include ordering information."
	                   @" Use appendObject or prependObject methods instead.", NSStringFromSelector(_cmd)];
}

#pragma mark Add

- (void)appendObject:(id)object forKey:(NSString *)key
{
	[self appendObject:object forKey:key withMetadata:nil];
}

- (void)appendObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
	}
	else
	{
		[transaction setObject:object forKey:key withMetadata:metadata];
		[connection->order appendKey:key transaction:self];
	}
}

- (void)prependObject:(id)object forKey:(NSString *)key
{
	[self prependObject:object forKey:key withMetadata:nil];
}

- (void)prependObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
	}
	else
	{
		[transaction setObject:object forKey:key withMetadata:metadata];
		[connection->order prependKey:key transaction:self];
	}
}

- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key
{
	[self insertObject:object atIndex:index forKey:key withMetadata:nil];
}

- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
	}
	else
	{
		[transaction setObject:object forKey:key withMetadata:metadata];
		[connection->order insertKey:key atIndex:index transaction:self];
	}
}

- (void)updateObject:(id)object forKey:(NSString *)key
{
	[self updateObject:object forKey:key withMetadata:nil];
}

- (void)updateObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key];
	}
	else if ([transaction hasObjectForKey:key]) // In-place update only
	{
		[transaction setObject:object forKey:key withMetadata:metadata];
		// No changes needed to database order, as key is already in order list.
	}
}

#pragma mark Remove

- (void)removeObjectForKey:(NSString *)key
{
	[transaction removeObjectForKey:key];
	[connection->order removeKey:key transaction:self];
}

- (void)removeObjectsForKeys:(NSArray *)keys
{
	[transaction removeObjectsForKeys:keys];
	[connection->order removeKeys:keys transaction:self];
}

- (void)removeAllObjects
{
	[transaction removeAllObjects];
	[connection->order removeAllKeys:self];
}

- (void)removeObjectAtIndex:(NSUInteger)index
{
	NSString *key = [connection->order removeKeyAtIndex:index transaction:self];
	[transaction removeObjectForKey:key];
}

- (void)removeObjectsInRange:(NSRange)range
{
	NSArray *keys = [connection->order removeKeysInRange:range transaction:self];
	[transaction removeObjectsForKeys:keys];
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
}

#pragma mark YapOrderReadWriteTransaction Protocol

- (void)setData:(NSData *)data forKey:(NSString *)key order:(YapDatabaseOrder *)sender
{
	if (data == nil)
	{
		[self removeDataForKey:key order:sender];
		return;
	}
	
	if (key == nil) return;
	
	sqlite3_stmt *statement = [connection setOrderDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "order" ("key", "data") VALUES (?, ?);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	sqlite3_bind_blob(statement, 2, data.bytes, data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'setOrderDataForKeyStatement': %d %s, key(%@)",
		                                                         status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
}

- (void)removeDataForKey:(NSString *)key order:(YapDatabaseOrder *)order
{
	if (key == nil) return;
	
	sqlite3_stmt *statement = [connection removeOrderDataForKeyStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "order" WHERE "key" = ?;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeOrderDataForKeyStatement': %d %s, key(%@)",
		                                                            status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
}

- (void)removeAllDataForOrder:(YapDatabaseOrder *)sender
{
	sqlite3_stmt *statement = [connection removeAllOrderDataStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "order";
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeAllOrderDataStatement': %d %s",
		                                                         status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
}

@end
