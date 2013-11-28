#import <Foundation/Foundation.h>

#import "YapCollectionsDatabaseViewTransaction.h"
#import "YapCollectionsDatabaseFilteredView.h"

#ifndef YapCollectionsDatabaseViewFilteringBlockDefined
#define YapCollectionsDatabaseViewFilteringBlockDefined 1

typedef id YapCollectionsDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapCollectionsDatabaseViewFilteringWithKeyBlock)     \
                                        (NSString *group, NSString *collection, NSString *key);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithObjectBlock)  \
                                        (NSString *group, NSString *collection, NSString *key, id object);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithMetadataBlock)\
                                        (NSString *group, NSString *collection, NSString *key, id metadata);
typedef BOOL (^YapCollectionsDatabaseViewFilteringWithRowBlock)     \
                                        (NSString *group, NSString *collection, NSString *key, id object, id metadata);

#endif


@interface YapCollectionsDatabaseFilteredViewTransaction : YapCollectionsDatabaseViewTransaction

// This class extends YapCollectionsDatabaseViewTransaction.
//
// Please see YapCollectionsDatabaseViewTransaction.h

@end

#pragma mark -

@interface YapCollectionsDatabaseFilteredViewTransaction (ReadWrite)

- (void)setFilteringBlock:(YapCollectionsDatabaseViewFilteringBlock)filteringBlock
       filteringBlockType:(YapCollectionsDatabaseViewBlockType)filteringBlockType
                      tag:(NSString *)tag;

@end
