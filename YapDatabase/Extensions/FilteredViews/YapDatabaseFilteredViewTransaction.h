#import <Foundation/Foundation.h>

#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseFilteredView.h"

#ifndef YapDatabaseViewFilteringBlockDefined
#define YapDatabaseViewFilteringBlockDefined 1

typedef id YapDatabaseViewFilteringBlock; // One of the YapDatabaseViewGroupingX types below.

typedef BOOL (^YapDatabaseViewFilteringWithKeyBlock)     \
                                        (NSString *group, NSString *collection, NSString *key);
typedef BOOL (^YapDatabaseViewFilteringWithObjectBlock)  \
                                        (NSString *group, NSString *collection, NSString *key, id object);
typedef BOOL (^YapDatabaseViewFilteringWithMetadataBlock)\
                                        (NSString *group, NSString *collection, NSString *key, id metadata);
typedef BOOL (^YapDatabaseViewFilteringWithRowBlock)     \
                                        (NSString *group, NSString *collection, NSString *key, id object, id metadata);

#endif


@interface YapDatabaseFilteredViewTransaction : YapDatabaseViewTransaction

// This class extends YapDatabaseViewTransaction.
//
// Please see YapDatabaseViewTransaction.h

@end

#pragma mark -

@interface YapDatabaseFilteredViewTransaction (ReadWrite)

- (void)setFilteringBlock:(YapDatabaseViewFilteringBlock)filteringBlock
       filteringBlockType:(YapDatabaseViewBlockType)filteringBlockType
                      tag:(NSString *)tag;

@end
