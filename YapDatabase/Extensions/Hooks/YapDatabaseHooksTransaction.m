#import "YapDatabaseHooksTransaction.h"
#import "YapDatabaseHooksPrivate.h"
#import "YapProxyObjectPrivate.h"


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
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)ck
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksInsertedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)ck
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)didReplaceObject:(id)object
        forCollectionKey:(YapCollectionKey *)ck
               withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRowid:rowid collectionKey:ck isMetadata:YES transaction:transaction];
		
		YapDatabaseHooksBitMask flags = YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)didReplaceMetadata:(id)metadata
          forCollectionKey:(YapCollectionKey *)ck
                 withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRowid:rowid collectionKey:ck isMetadata:NO transaction:transaction];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags = YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedMetadata;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRowid:rowid collectionKey:ck isMetadata:NO transaction:transaction];
		[proxyMetadata resetWithRowid:rowid collectionKey:ck isMetadata:YES transaction:transaction];
		
		YapDatabaseHooksBitMask flags = YapDatabaseHooksTouchedObject;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRowid:rowid collectionKey:ck isMetadata:NO transaction:transaction];
		[proxyMetadata resetWithRowid:rowid collectionKey:ck isMetadata:YES transaction:transaction];
		
		YapDatabaseHooksBitMask flags = YapDatabaseHooksTouchedMetadata;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchRowForKey:inCollection:
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidModifyRow didModifyRow = parentConnection->parent.didModifyRow;
	if (didModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRowid:rowid collectionKey:ck isMetadata:NO transaction:transaction];
		[proxyMetadata resetWithRowid:rowid collectionKey:ck isMetadata:YES transaction:transaction];
		
		YapDatabaseHooksBitMask flags = YapDatabaseHooksTouchedObject | YapDatabaseHooksTouchedMetadata;
		
		didModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction
 * - removeObjectForKey:inCollection:
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_DidRemoveRow didRemoveRow = parentConnection->parent.didRemoveRow;
	if (didRemoveRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		didRemoveRow(transaction, ck.collection, ck.key);
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
- (void)didRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	YDBHooks_DidRemoveRow didRemoveRow = parentConnection->parent.didRemoveRow;
	if (didRemoveRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		for (NSString *key in keys)
		{
			didRemoveRow(transaction, collection, key);
		}
	}
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to [transaction removeAllObjectsInAllCollections].
**/
- (void)didRemoveAllObjectsInAllCollections
{
	YDBHooks_DidRemoveAllRows didRemoveAllRows = parentConnection->parent.didRemoveAllRows;
	if (didRemoveAllRows)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		didRemoveAllRows(transaction);
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
- (void)willInsertObject:(id)object
        forCollectionKey:(YapCollectionKey *)ck
            withMetadata:(id)metadata
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_WillModifyRow willModifyRow = parentConnection->parent.willModifyRow;
	if (willModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksInsertedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		willModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)willUpdateObject:(id)object
        forCollectionKey:(YapCollectionKey *)ck
            withMetadata:(id)metadata
                   rowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_WillModifyRow willModifyRow = parentConnection->parent.willModifyRow;
	if (willModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject | YapDatabaseHooksChangedMetadata;
		
		willModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)willReplaceObject:(id)object
         forCollectionKey:(YapCollectionKey *)ck
                withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_WillModifyRow willModifyRow = parentConnection->parent.willModifyRow;
	if (willModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRealObject:object];
		[proxyMetadata resetWithRowid:rowid collectionKey:ck isMetadata:YES transaction:transaction];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedObject;
		
		willModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
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
- (void)willReplaceMetadata:(id)metadata
           forCollectionKey:(YapCollectionKey *)ck
                  withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_WillModifyRow willModifyRow = parentConnection->parent.willModifyRow;
	if (willModifyRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		if (proxyObject == nil)
			proxyObject = [[YapProxyObject alloc] init];
		
		if (proxyMetadata == nil)
			proxyMetadata = [[YapProxyObject alloc] init];
		
		[proxyObject resetWithRowid:rowid collectionKey:ck isMetadata:NO transaction:transaction];
		[proxyMetadata resetWithRealObject:metadata];
		
		YapDatabaseHooksBitMask flags =
		  YapDatabaseHooksUpdatedRow | YapDatabaseHooksChangedMetadata;
		
		willModifyRow(transaction, ck.collection, ck.key, proxyObject, proxyMetadata, flags);
		
		[proxyObject reset];
		[proxyMetadata reset];
	}
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked pre-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
**/
- (void)willRemoveObjectForCollectionKey:(YapCollectionKey *)ck withRowid:(int64_t)rowid
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:ck.collection])
	{
		return;
	}
	
	YDBHooks_WillRemoveRow willRemoveRow = parentConnection->parent.willRemoveRow;
	if (willRemoveRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		willRemoveRow(transaction, ck.collection, ck.key);
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
- (void)willRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	__unsafe_unretained YapWhitelistBlacklist *allowedCollections = parentConnection->parent->allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	YDBHooks_WillRemoveRow willRemoveRow = parentConnection->parent.willRemoveRow;
	if (willRemoveRow)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		for (NSString *key in keys)
		{
			willRemoveRow(transaction, collection, key);
		}
	}
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
	YDBHooks_WillRemoveAllRows willRemoveAllRows = parentConnection->parent.willRemoveAllRows;
	if (willRemoveAllRows)
	{
		__unsafe_unretained YapDatabaseReadWriteTransaction *transaction =
		  (YapDatabaseReadWriteTransaction *)databaseTransaction;
		
		willRemoveAllRows(transaction);
	}
}

@end
