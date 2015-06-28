#import <Foundation/Foundation.h>


/**
 * Specifies the kind of block being used.
**/
typedef NS_ENUM(NSInteger, YapDatabaseRTreeIndexBlockType) {
	YapDatabaseRTreeIndexBlockTypeWithKey       = 1131,
	YapDatabaseRTreeIndexBlockTypeWithObject    = 1132,
	YapDatabaseRTreeIndexBlockTypeWithMetadata  = 1133,
	YapDatabaseRTreeIndexBlockTypeWithRow       = 1134
};


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

typedef void (^YapDatabaseRTreeIndexWithKeyBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);
typedef void (^YapDatabaseRTreeIndexWithObjectBlock)   \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);
typedef void (^YapDatabaseRTreeIndexWithMetadataBlock) \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id metadata);
typedef void (^YapDatabaseRTreeIndexWithRowBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseRTreeIndexWithKeyBlock)block;
+ (instancetype)withObjectBlock:(YapDatabaseRTreeIndexWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(YapDatabaseRTreeIndexWithMetadataBlock)block;
+ (instancetype)withRowBlock:(YapDatabaseRTreeIndexWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseRTreeIndexBlock block;
@property (nonatomic, assign, readonly) YapDatabaseRTreeIndexBlockType blockType;

@end
