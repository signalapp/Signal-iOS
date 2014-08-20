#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewMappings.h"

/**
 * This header file is PRIVATE, and is only to be used by the YapDatabaseView classes.
**/

@interface YapDatabaseViewSectionChange () {
@public
	
	// This header file is PRIVATE, and is only to be used by YapDatabaseView classes
	
	NSString *group; // immutable
	BOOL isReset;    // immutable
	
	YapDatabaseViewChangeType type; // mutable during consolidation
	
	NSUInteger originalSection; // mutable during pre-processing
	NSUInteger finalSection;    // mutable during pre-processing
}

+ (YapDatabaseViewSectionChange *)insertGroup:(NSString *)group;
+ (YapDatabaseViewSectionChange *)deleteGroup:(NSString *)group;

+ (YapDatabaseViewSectionChange *)resetGroup:(NSString *)group;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewRowChange () {
@public
	
	// This header file is PRIVATE, and is only to be used by YapDatabaseView classes
	
	YapCollectionKey *collectionKey; // immutable
	
	NSString *originalGroup; // immutable
	NSString *finalGroup;    // mutable during consolidation
	
	YapDatabaseViewChangeType type;        // mutable during consolidation
	YapDatabaseViewChangesBitMask changes; // mutable during consolidation
	
	NSUInteger opOriginalIndex;  // immutable
	NSUInteger opFinalIndex;     // immutable
	
	NSUInteger originalIndex; // mutable during processing
	NSUInteger finalIndex;    // mutable during processing
	
	NSUInteger originalSection; // mutable during pre-processing
	NSUInteger finalSection;    // mutable during pre-processing
}

/**
 * During a transaction, there are only 3 row change types that may be recorded.
 *
 * Post-processing figures out everything else, such as if an item was moved,
 * or if multiple operations can be consolidated into one.
**/

+ (YapDatabaseViewRowChange *)insertCollectionKey:(YapCollectionKey *)key
                                          inGroup:(NSString *)group
                                          atIndex:(NSUInteger)index;

+ (YapDatabaseViewRowChange *)deleteCollectionKey:(YapCollectionKey *)key
                                          inGroup:(NSString *)group
                                          atIndex:(NSUInteger)index;

+ (YapDatabaseViewRowChange *)updateCollectionKey:(YapCollectionKey *)ck
                                          inGroup:(NSString *)group
                                          atIndex:(NSUInteger)index
                                      withChanges:(YapDatabaseViewChangesBitMask)flags;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewChange : NSObject

/**
 * The brains behind the post-processing logic.
 * Exposed privately to be used by the unit tests.
**/
+ (void)processRowChanges:(NSMutableArray *)rowChanges
     withOriginalMappings:(YapDatabaseViewMappings *)originalMappings
            finalMappings:(YapDatabaseViewMappings *)finalMappings;
+ (void)consolidateRowChanges:(NSMutableArray *)changes;

/**
 * This method applies the given mappings, and then invokes the post-processing method.
 * 
 * This method is ONLY to be used by YapDatabaseViewConnection.
**/
+ (void)getSectionChanges:(NSArray **)sectionChangesPtr
               rowChanges:(NSArray **)rowChangesPtr
	 withOriginalMappings:(YapDatabaseViewMappings *)originalMappings
			finalMappings:(YapDatabaseViewMappings *)finalMappings
			  fromChanges:(NSArray *)changes;

@end
