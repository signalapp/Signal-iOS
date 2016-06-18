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

@end
