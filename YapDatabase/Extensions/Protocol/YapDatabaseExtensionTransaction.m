#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * An extension transaction is where a majority of the action happens.
 * Subclasses will list the majority of their public API within the transaction.
 *
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *
 *     object = [[transaction ext:@"view"] objectAtIndex:index inGroup:@"sales"];
 *     //         ^^^^^^^^^^^^^^^^^^^^^^^
 *     //         ^ Returns a YapDatabaseExtensionTransaction subclass instance.
 * }];
 *
 * An extension transaction has a reference to the database transction (and therefore to sqlite),
 * as well as a reference to its parent extension connection. It is the same in architecture as
 * database connections and transactions. That is, all access (read-only or read-write) goes
 * through a transaction. Further, each connection only has a single transaction at a time.
 * Thus transactions are optimized by storing a majority of their state within their respective connection.
 *
 * An extension transaction is created on-demand (or as needed) from within a database transaction.
 *
 * During a read-only transaction:
 * - If the extension is not requested, then it is not created.
 * - If the extension is requested, it is created once per transaction.
 * - Additional requests for the same extension return the existing instance.
 *
 * During a read-write transaction:
 * - If a modification to the database is initiated,
 *   every registered extension has an associated transaction created in order to handle the associated hook calls.
 * - If the extension is requested, it is created once per transaction.
 * - Additional requests for the same extension return the existing instance.
 *
 * The extension transaction is only valid from within the database transaction.
**/
@implementation YapDatabaseExtensionTransaction {
	
// You MUST store an unretained reference to the parent.
// You MUST store an unretained reference to the corresponding database transaction.
//
// Yours should be similar to the example below, but typed according to your needs.

/* Example from YapDatabaseViewTransaction
 
@private
    __unsafe_unretained YapDatabaseViewConnection *viewConnection;
    __unsafe_unretained YapDatabaseTransaction *databaseTransaction;
 
*/
}

#pragma mark Creation

/**
 * Subclasses MUST implement this method.
 * 
 * This method is called during the registration process.
 * Subclasses should perform any tasks needed in order to setup the extension for use by other connections.
 *
 * This includes creating any necessary tables,
 * as well as possibly populating the tables by enumerating over the existing rows in the database.
 * 
 * The method should check to see if it has already been created.
 * That is, is this a re-registration from a previous app launch,
 * or is this the first time the extension has been registered under this name?
 * 
 * The recommended way of accomplishing this is via the yap2 table (which was designed for this purpose).
 * There are various convenience methods that allow you store various settings about your extension in this table.
 * See 'intValueForExtensionKey:' and other related methods.
 * 
 * Note: This method is invoked on a special readWriteTransaction that is created internally
 * within YapDatabase for the sole purpose of registering and unregistering extensions.
 * So this method need not setup itself for regular use.
 * It is designed only to do the prep work of creating the extension dependencies (such as tables)
 * so that regular instances (possibly read-only) can operate normally.
 *
 * See YapDatabaseViewTransaction for a reference implementation.
 * 
 * Return YES if completed successfully, or if already created.
 * Return NO if some kind of error occured.
**/
- (BOOL)createIfNeeded
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * Subclasses MUST implement this method.
 *
 * This method is invoked in order to prepare an extension transaction for use.
 * Remember, transactions are short lived instances.
 * So an extension transaction should store the vast majority of its state information within the extension connection.
 * Thus an extension transaction instance should generally only need to prepare itself once. (*)
 * It should store preparation info in the connection.
 * And future invocations of this method will see that the connection has all the prepared state it needs,
 * and then this method will return immediately.
 *
 * (*) an exception to this rule may occur if the user aborts a read-write transaction (via rollback),
 *     and the extension connection must dump all its prepared state.
 *
 * Changes that occur on other connections should get incorporated via the changeset architecture
 * from within the extension connection subclass.
 *
 * This method may be invoked on a read-only OR read-write transaction.
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Commit & Rollback
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should ONLY implement this method if they need to make changes to the 'database' table.
 * That is, the main collection/key/value table that directly stores the user's objects.
 *
 * Return NO if the extension does not directly modify the main database table.
 * Return YES if the extension does modify the main database table,
 * regardless of whether it made changes during this invocation.
 *
 * This method may be invoked several times in a row.
**/
- (BOOL)flushPendingChangesToMainDatabaseTable
{
	// Override me if needed
	return NO;
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should write any last changes to their database table(s) if needed,
 * and should perform any needed cleanup before the changeset is requested.
 * 
 * Remember, the changeset is requested immediately after this method is invoked.
**/
- (void)flushPendingChangesToExtensionTables
{
	// Override me if needed
}

/**
 * Subclasses MUST implement this method.
 * This method is only called if within a readwrite transaction.
 * 
 * Remember, the transaction cannot make any changes to the database at this point,
 * as this method is called after the transaction has completed.
 * This method is primarily for cleanup & related tasks.
**/
- (void)didCommitTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	// Subclasses MUST include the code similar to the following at the end of their implementation:
	//
	// extConnection = nil;
	// databaseTransaction = nil;
}

/**
 * Subclasses MUST implement this method.
 * This method is only called if within a readwrite transaction.
 * 
 * Remember, the transaction cannot make any changes to the database at this point,
 * as this method is called after the transaction has aborted.
 * This method is primarily for cleanup & related tasks.
**/
- (void)didRollbackTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	// Subclasses MUST include the code similar to the following at the end of their implementation:
	//
	// extConnection = nil;
	// databaseTransaction = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Generic Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement these methods.
 * They are needed by various utility methods.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

/**
 * Subclasses MUST implement these methods.
 * They are needed by various utility methods.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being inserted, meaning there is not currently an entry for the collection/key tuple.
**/
- (void)didInsertObject:(id __unused)object
       forCollectionKey:(YapCollectionKey __unused *)collectionKey
           withMetadata:(id __unused)metadata
                  rowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being modified, meaning there is already an entry for the collection/key tuple which is being modified.
**/
- (void)didUpdateObject:(id __unused)object
       forCollectionKey:(YapCollectionKey __unused *)collectionKey
           withMetadata:(id __unused)metadata
                  rowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
 * 
 * There is already a row for the collection/key tuple, and only the object is being modified (metadata untouched).
**/
- (void)didReplaceObject:(id __unused)object
        forCollectionKey:(YapCollectionKey __unused *)collectionKey
               withRowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
 * 
 * There is already a row for the collection/key tuple, and only the metadata is being modified (object untouched).
**/
- (void)didReplaceMetadata:(id __unused)metadata
          forCollectionKey:(YapCollectionKey __unused *)collectionKey
                 withRowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction
 * - removeObjectForKey:inCollection:
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
 *
 * IMPORTANT:
 *   The number of items passed to this method has the following guarantee:
 *   count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
 * 
 * The YapDatabaseReadWriteTransaction will inspect the list of keys that are to be removed,
 * and then loop over them in "chunks" which are readily processable for extensions.
**/
- (void)didRemoveObjectsForKeys:(NSArray __unused *)keys
                   inCollection:(NSString __unused *)collection
                     withRowids:(NSArray __unused *)rowids
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to [transaction removeAllObjectsInAllCollections].
**/
- (void)didRemoveAllObjectsInAllCollections
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pre-Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being inserted, meaning there is not currently an entry for the collection/key tuple.
**/
- (void)willInsertObject:(id)object
        forCollectionKey:(YapCollectionKey *)collectionKey
            withMetadata:(id)metadata
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
 *
 * The row is being modified, meaning there is already an entry for the collection/key tuple which is being modified.
**/
- (void)willUpdateObject:(id)object
        forCollectionKey:(YapCollectionKey *)collectionKey
            withMetadata:(id)metadata
                   rowid:(int64_t)rowid
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
 *
 * There is already a row for the collection/key tuple, and only the object is being modified (metadata untouched).
**/
- (void)willReplaceObject:(id)object
         forCollectionKey:(YapCollectionKey *)collectionKey
                withRowid:(int64_t)rowid
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
 *
 * There is already a row for the collection/key tuple, and only the metadata is being modified (object untouched).
**/
- (void)willReplaceMetadata:(id)metadata
           forCollectionKey:(YapCollectionKey *)collectionKey
                  withRowid:(int64_t)rowid
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
**/
- (void)willRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
 *
 * IMPORTANT:
 *   The number of items passed to this method has the following guarantee:
 *   count <= (SQLITE_LIMIT_VARIABLE_NUMBER - 1)
 *
 * The YapDatabaseReadWriteTransaction will inspect the list of keys that are to be removed,
 * and then loop over them in "chunks" which are readily processable for extensions.
**/
- (void)willRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	// Override me if needed
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeAllObjectsInAllCollections
**/
- (void)willRemoveAllObjectsInAllCollections
{
	// Override me if needed
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration Values
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The following are convenience methods for getting and setting configuration values for the extension.
 * You may choose to store configuration info either persistently (in database), or non-persistently (in memory only).
 * 
 * Persistent values are stored in the yap2 sqlite table.
 * Non-persistent values are stored in a YapMemoryTable.
 *
 * The yap2 sqlite table is structured like this:
 *
 * CREATE TABLE IF NOT EXISTS "yap2" (
 *   "extension" CHAR NOT NULL,
 *   "key" CHAR NOT NULL,
 *   "data" BLOB,
 *   PRIMARY KEY ("extension", "key")
 * );
 *
 * You pass the "key" and the "data" (which can be typed however you want it to be such as int, string, etc).
 * The "extension" value is automatically set to the registeredName of the extension.
 *
 * Usage example:
 *
 *   The View extension stores a "versionTag" which is given to it during the init method by the user.
 *   If the "versionTag" changes, this signifies that the user has changed something about the view,
 *   such as the sortingBlock or groupingBlock. The view then knows to flush its tables and re-populate them.
 *   It stores the "versionTag" in the yap2 table via the methods below.
 *
 * When an extension is unregistered, either manually or automatically (if orphaned),
 * then the database system automatically deletes all values from the yap2 table where extension == registeredName.
**/

- (BOOL)getBoolValue:(BOOL *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getBoolValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] yapMemoryTableTransaction] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object boolValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = NO;
			return NO;
		}
	}
}

- (BOOL)boolValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	BOOL value = NO;
	[self getBoolValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setBoolValue:(BOOL)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setBoolValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (BOOL)getIntValue:(int *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getIntValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] yapMemoryTableTransaction] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object intValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = 0;
			return NO;
		}
	}
}

- (int)intValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	int value = 0;
	[self getIntValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setIntValue:(int)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setIntValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (BOOL)getDoubleValue:(double *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getDoubleValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] yapMemoryTableTransaction] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object doubleValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = 0.0;
			return NO;
		}
	}
}

- (double)doubleValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	double value = 0.0;
	[self getDoubleValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setDoubleValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (NSString *)stringValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] stringValueForKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] yapMemoryTableTransaction] objectForKey:ck];
		
		if ([object isKindOfClass:[NSString class]])
			return object;
		if ([object isKindOfClass:[NSNumber class]])
			return [(NSNumber *)object stringValue];
		
		return nil;
	}
}

- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setStringValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] setObject:value forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (NSData *)dataValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] dataValueForKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] yapMemoryTableTransaction] objectForKey:ck];
		
		if ([object isKindOfClass:[NSData class]])
			return (NSData *)object;
		else
			return nil;
	}
}

- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setDataValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] setObject:value forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (void)removeValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction removeValueForKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction yapMemoryTableTransaction] removeObjectForKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

@end
