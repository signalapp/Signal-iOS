#import "YapDatabaseHooksTransaction.h"
#import "YapDatabaseHooksPrivate.h"


@implementation YapDatabaseHooksTransaction

- (id)initWithParentConnection:(YapDatabaseHooksConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		parentConnection = inParentConnection;
		databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Creation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement this method.
**/
- (BOOL)createIfNeeded
{
	// Nothing to do here
	return YES;
}

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement this method.
**/
- (BOOL)prepareIfNeeded
{
	// Nothing to do here
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Commit & Rollback
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement this method.
**/
- (void)didCommitTransaction
{
	parentConnection = nil;
	databaseTransaction = nil;
}

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement this method.
**/
- (void)didRollbackTransaction
{
	parentConnection = nil;
	databaseTransaction = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Generic Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement these methods.
 * They are needed by various utility methods.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	return databaseTransaction;
}

/**
 * YapDatabaseExtensionTransaction subclasses MUST implement these methods.
 * They are needed by various utility methods.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	return parentConnection;
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
- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)ck
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	if (parentConnection->parent->didInsertObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didInsertObject(transaction, ck.collection, ck.key, object, metadata);
	}
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
- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)ck
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid
{
	if (parentConnection->parent->didUpdateObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didUpdateObject(transaction, ck.collection, ck.key, object, metadata);
	}
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
- (void)handleReplaceObject:(id)object
           forCollectionKey:(YapCollectionKey *)ck
                  withRowid:(int64_t)rowid
{
	if (parentConnection->parent->didReplaceObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didReplaceObject(transaction, ck.collection, ck.key, object);
	}
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
- (void)handleReplaceMetadata:(id)metadata
             forCollectionKey:(YapCollectionKey *)ck
                    withRowid:(int64_t)rowid
{
	if (parentConnection->parent->didReplaceMetadata)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didReplaceMetadata(transaction, ck.collection, ck.key, metadata);
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	// Nothing to do here
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	// Nothing to do here
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction
 * - removeObjectForKey:inCollection:
**/
- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	if (parentConnection->parent->didRemoveObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didRemoveObject(transaction, ck.collection, ck.key);
	}
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
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	if (parentConnection->parent->didRemoveObjects)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didRemoveObjects(transaction, collection, keys);
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to [transaction removeAllObjectsInAllCollections].
**/
- (void)handleRemoveAllObjectsInAllCollections
{
	if (parentConnection->parent->didRemoveAllObjectsInAllCollections)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->didRemoveAllObjectsInAllCollections(transaction);
	}
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
- (void)handleWillInsertObject:(id)object
              forCollectionKey:(YapCollectionKey *)ck
                  withMetadata:(id)metadata
{
	if (parentConnection->parent->willInsertObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willInsertObject(transaction, ck.collection, ck.key, object, metadata);
	}
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
- (void)handleWillUpdateObject:(id)object
              forCollectionKey:(YapCollectionKey *)ck
                  withMetadata:(id)metadata
                         rowid:(int64_t)rowid
{
	if (parentConnection->parent->willUpdateObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willUpdateObject(transaction, ck.collection, ck.key, object, metadata);
	}
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
- (void)handleWillReplaceObject:(id)object
               forCollectionKey:(YapCollectionKey *)ck
                      withRowid:(int64_t)rowid
{
	if (parentConnection->parent->willReplaceObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willReplaceObject(transaction, ck.collection, ck.key, object);
	}
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
- (void)handleWillReplaceMetadata:(id)metadata
                 forCollectionKey:(YapCollectionKey *)ck
                        withRowid:(int64_t)rowid
{
	if (parentConnection->parent->willReplaceMetadata)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willReplaceMetadata(transaction, ck.collection, ck.key, metadata);
	}
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
**/
- (void)handleWillRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	if (parentConnection->parent->willRemoveObject)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willRemoveObject(transaction, ck.collection, ck.key);
	}
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
- (void)handleWillRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	if (parentConnection->parent->willRemoveObjects)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willRemoveObjects(transaction, collection, keys);
	}
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeAllObjectsInAllCollections
**/
- (void)handleWillRemoveAllObjectsInAllCollections
{
	if (parentConnection->parent->willRemoveAllObjectsInAllCollections)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		parentConnection->parent->willRemoveAllObjectsInAllCollections(transaction);
	}
}

@end
