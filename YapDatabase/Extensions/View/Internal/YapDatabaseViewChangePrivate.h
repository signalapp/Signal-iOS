#import "YapDatabaseViewChange.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/
@interface YapDatabaseViewChange ()

/**
 * During a transaction, there are only 3 change types that may be recorded.
 *
 * Post-processing figures out everything else, such as if an item was moved,
 * or if multiple operations can be consolidated into one.
**/

+ (YapDatabaseViewChange *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;
+ (YapDatabaseViewChange *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;

+ (YapDatabaseViewChange *)updateKey:(id)key columns:(int)flags inGroup:(NSString *)group atIndex:(NSUInteger)index;

/**
 * The brains behind all the post-processing logic.
 * Exposed privately to be used by the unit tests.
**/
+ (void)processAndConsolidateChanges:(NSMutableArray *)changes;

/**
 * This method applies the given mappings, and then invokes the post-processing method.
 * 
 * This method is ONLY to be used by YapDatabaseViewConnection & YapCollectionsDatabaseViewConnection.
 * 
 * Important:
 * - This method alters the YapDatabaseViewChange objects in the given array.
 *   Therefore, the objects that are passed MUST be COPIED from the changeset array.
**/
+ (void)processAndConsolidateChanges:(NSMutableArray *)changes
             withGroupToSectionMappings:(NSDictionary *)mappings;

@end
