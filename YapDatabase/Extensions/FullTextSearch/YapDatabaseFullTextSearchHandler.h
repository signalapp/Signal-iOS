#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The handler block handles extracting the column values for indexing by the FTS module.
 *
 * When you add or update rows in the databse the FTS block is invoked.
 * Your block can inspect the row and determine if it contains any text columns that should be indexed.
 * If not, the  block can simply return.
 * Otherwise the block should extract any text values, and add them to the given dictionary.
 *
 * After the block returns, the dictionary parameter will be inspected,
 * and any set values will be automatically passed to sqlite's FTS module for indexing.
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The extension can make various optimizations based on the required parameters of the block.
**/
@interface YapDatabaseFullTextSearchHandler : NSObject

typedef id YapDatabaseFullTextSearchBlock; // One of YapDatabaseFullTextSearchXBlock types

typedef void (^YapDatabaseFullTextSearchWithKeyBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);

typedef void (^YapDatabaseFullTextSearchWithObjectBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);

typedef void (^YapDatabaseFullTextSearchWithMetadataBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, __nullable id metadata);

typedef void (^YapDatabaseFullTextSearchWithRowBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, __nullable id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseFullTextSearchWithKeyBlock)block;
+ (instancetype)withObjectBlock:(YapDatabaseFullTextSearchWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(YapDatabaseFullTextSearchWithMetadataBlock)block;
+ (instancetype)withRowBlock:(YapDatabaseFullTextSearchWithRowBlock)block;

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseFullTextSearchWithKeyBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseFullTextSearchWithObjectBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseFullTextSearchWithMetadataBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseFullTextSearchWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseFullTextSearchBlock block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType           blockType;
@property (nonatomic, assign, readonly) YapDatabaseBlockInvoke         blockInvokeOptions;

@end

NS_ASSUME_NONNULL_END
