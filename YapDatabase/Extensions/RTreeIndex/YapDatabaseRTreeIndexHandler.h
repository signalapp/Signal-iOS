#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTypes.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * The handler block handles extracting the column values for the rtree index.
 *
 * When you add or update rows in the databse the block is invoked.
 * Your block can inspect the row and determine if it contains any values that should be added to the rtree index.
 * If not, the  block can simply return.
 * Otherwise the block should add a min and max value (can be equal) for each indexed dimension to the given dictionary.
 *
 * After the block returns, the dictionary parameter will be inspected,
 * and any set values will be automatically inserted/updated within the sqlite index.
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The extension can make various optimizations based on required parameters of the block.
 * For example, if metadata isn't required, then the extension can ignore metadata-only updates.
**/
@interface YapDatabaseRTreeIndexHandler : NSObject

typedef id YapDatabaseRTreeIndexBlock; // One of the YapDatabaseRTreeIndexWith_X_Block types below.

typedef void (^YapDatabaseRTreeIndexWithKeyBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);

typedef void (^YapDatabaseRTreeIndexWithObjectBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);

typedef void (^YapDatabaseRTreeIndexWithMetadataBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, __nullable id metadata);

typedef void (^YapDatabaseRTreeIndexWithRowBlock)
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, __nullable id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block;
+ (instancetype)withObjectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block;
+ (instancetype)withRowBlock:(YapDatabaseRTreeIndexWithRowBlock)block;

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseRTreeIndexWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseRTreeIndexBlock block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType       blockType;
@property (nonatomic, assign, readonly) YapDatabaseBlockInvoke     blockInvokeOptions;

@end

NS_ASSUME_NONNULL_END
