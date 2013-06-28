#import "YapDatabaseViewOperation.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/
@interface YapDatabaseViewOperation ()

/**
 * During a transaction, there are only 3 types of operations that may be recorded.
 *
 * Post-processing figures out everything else, such as if an item was moved,
 * or if multiple operations can be consolidated into one.
**/

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;
+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;

+ (YapDatabaseViewOperation *)updateKey:(id)key columns:(int)flags inGroup:(NSString *)group atIndex:(NSUInteger)index;

/**
 * The brains behind all the post-processing logic.
 * Exposed privately to be used by the unit tests.
**/
+ (void)processAndConsolidateOperations:(NSMutableArray *)operations;

/**
 * This method applies the given mappings, and then invokes the post-processing method.
 * 
 * This method is ONLY to be used by YapDatabaseViewConnection & YapCollectionsDatabaseViewConnection.
 * 
 * Important:
 * - This method alters the YapDatabaseViewOperation objects in the given array.
 *   Therefore, the objects that are passed MUST be COPIED from the changeset array.
**/
+ (void)processAndConsolidateOperations:(NSMutableArray *)operations
             withGroupToSectionMappings:(NSDictionary *)mappings;

@end
