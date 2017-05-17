#import "YapDatabaseManualViewTransaction.h"
#import "YapDatabaseManualViewPrivate.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

@implementation YapDatabaseManualViewTransaction

#pragma mark Extension Lifecycle

/**
 * Required override method from YapDatabaseViewTransaction.
**/
- (BOOL)populateView
{
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)_didChangeWithRowid:(int64_t)rowid
              collectionKey:(YapCollectionKey *)collectionKey
             changesBitMask:(YapDatabaseViewChangesBitMask)changesBitMask
{
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	
	if (allowedCollections && ![allowedCollections isAllowed:collectionKey.collection])
	{
		return;
	}
	
	// Process as usual
	
	YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
	if (locator)
	{
		[parentConnection->changes addObject:
		  [YapDatabaseViewRowChange updateCollectionKey:collectionKey
		                                        inGroup:locator.group
		                                        atIndex:locator.index
		                                    withChanges:changesBitMask]];
	}
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Nothing to do here.
	// Since this is an insert, it means the object is new, and thus doesn't exist in our view.
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchObjectForKey:inCollection:collection:
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
}

/**
 * Subclasses MUST implement this method.
 * YapDatabaseReadWriteTransaction Hook, invoked post-op.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - touchMetadataForKey:inCollection:
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedMetadata;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
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
	YDBLogAutoTrace();
	
	YapDatabaseViewChangesBitMask changesBitMask = YapDatabaseViewChangedObject | YapDatabaseViewChangedMetadata;
	
	[self _didChangeWithRowid:rowid
	            collectionKey:collectionKey
	           changesBitMask:changesBitMask];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{
	YDBLogAutoTrace();
	
	// Should we ignore the row based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collectionKey.collection])
	{
		return;
	}
	
	// Process as usual
	
	[self removeRowid:rowid collectionKey:collectionKey];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{
	YDBLogAutoTrace();
	
	// Should we ignore the rows based on the allowedCollections ?
	
	YapWhitelistBlacklist *allowedCollections = parentConnection->parent->options.allowedCollections;
	if (allowedCollections && ![allowedCollections isAllowed:collection])
	{
		return;
	}
	
	// Process as usual
	
	NSMutableDictionary *collectionKeys = [NSMutableDictionary dictionaryWithCapacity:keys.count];
	
	[rowids enumerateObjectsUsingBlock:^(NSNumber *rowidNumber, NSUInteger idx, BOOL *stop) {
		
		NSString *key = [keys objectAtIndex:idx];
		
		collectionKeys[rowidNumber] = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	}];
	
	NSDictionary *locators = [self locatorsForRowids:rowids];
	
	[self removeRowidsWithCollectionKeys:collectionKeys locators:locators];
}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveAllObjectsInAllCollections
{
	YDBLogAutoTrace();
	
	[self removeAllRowids];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Adds the <collection, key> tuple to the end of the group (greatest index possible).
 *
 * The operation will fail if the <collection, key> already exists in the view,
 * regardless of whether it's in the given group, or another group.
 *
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)addKey:(NSString *)key inCollection:(NSString *)collection toGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	if (key == nil) return NO;
	if (group == nil) return NO;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return NO;
	}
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forCollectionKey:collectionKey]) {
		return NO;
	}
	
	if ([self containsRowid:rowid]) {
		return NO;
	}
	
	NSUInteger lastIndex = [self numberOfItemsInGroup:group];
	[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:lastIndex];
	
	return YES;
}

/**
 * Inserts the <collection, key> tuple in the group, placing it at the given index.
 * 
 * The operation will fail if the <collection, key> already exists in the view,
 * regardless of whether it's in the given group, or another group.
 * 
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)insertKey:(NSString *)key
     inCollection:(NSString *)collection
          atIndex:(NSUInteger)index
          inGroup:(NSString *)group
{
	if (key == nil) return NO;
	if (group == nil) return NO;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return NO;
	}
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forCollectionKey:collectionKey]) {
		return NO;
	}
	
	if ([self containsRowid:rowid]) {
		return NO;
	}
	
	NSUInteger count = [self numberOfItemsInGroup:group];
	if (index > count) {
		return NO;
	}
	
	[self insertRowid:rowid collectionKey:collectionKey inGroup:group atIndex:index];
	
	return YES;
}

/**
 * Removes the item currently located at the index in the given group.
 *
 * @return
 *   YES if the operation was successful (the group + index was valid). NO otherwise.
**/
- (BOOL)removeItemAtIndex:(NSUInteger)index inGroup:(NSString *)group
{
	if (group == nil) return NO;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return NO;
	}
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid atIndex:index inGroup:group]) {
		return NO;
	}
	
	YapCollectionKey *collectionKey = [databaseTransaction collectionKeyForRowid:rowid];
	
	[self removeRowid:rowid collectionKey:collectionKey atIndex:index inGroup:group];
	
	return YES;
}

/**
 * Removes the <collection, key> tuple from its index within the given group.
 * 
 * The operation will fail if the <collection, key> isn't currently a member of the group.
 *
 * @return
 *   YES if the operation was successful. NO otherwise.
**/
- (BOOL)removeKey:(NSString *)key inCollection:(NSString *)collection fromGroup:(NSString *)group
{
	if (key == nil) return NO;
	if (group == nil) return NO;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogWarn(@"%@ - Method only allowed in readWrite transaction", THIS_METHOD);
		return NO;
	}
	
	YapCollectionKey *collectionKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	int64_t rowid = 0;
	if (![databaseTransaction getRowid:&rowid forCollectionKey:collectionKey]) {
		return NO;
	}
	
	YapDatabaseViewLocator *locator = [self locatorForRowid:rowid];
	
	if (locator == nil) {
		return NO;
	}
	
	if (![locator.group isEqualToString:group]) {
		return NO;
	}
	
	[self removeRowid:rowid collectionKey:collectionKey withLocator:locator];
	
	return YES;
}

/**
 * Removes all <collection, key> tuples from the given group.
**/
- (void)removeAllItemsInGroup:(NSString *)group
{
	YDBLogAutoTrace();
	
	[self removeAllRowidsInGroup:group];
}

@end
