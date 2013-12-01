#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseFullTextSearchConnection.h"
#import "YapDatabaseFullTextSearchTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseFullTextSearch is an extension for performing text based search.
 * Internally it uses sqlite's FTS module which was contributed by Google.
**/

/**
 * The block handles extracting the column values for indexing by the FTS module.
 *
 * When you add or update rows in the databse the FTS block is invoked.
 * Your block can inspect the row and determine if it contains any text columns that should be indexed.
 * If not, the  block can simply return.
 * Otherwise the block should extract any text values, add them to the given dictionary.
 * 
 * After the block returns, the dictionary parameter will be inspected,
 * and any set values will be automatically passed to sqlite's FTS module for indexing.
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The view can make various optimizations based on required parameters of the block.
**/
typedef id YapDatabaseFullTextSearchBlock; // One of YapDatabaseFullTextSearchXBlock types

typedef void (^YapDatabaseFullTextSearchWithKeyBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);
typedef void (^YapDatabaseFullTextSearchWithObjectBlock)   \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);
typedef void (^YapDatabaseFullTextSearchWithMetadataBlock) \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id metadata);
typedef void (^YapDatabaseFullTextSearchWithRowBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, id metadata);

/**
 * Use this enum to specify what kind of block you're passing.
**/
typedef enum {
	YapDatabaseFullTextSearchBlockTypeWithKey       = 201,
	YapDatabaseFullTextSearchBlockTypeWithObject    = 202,
	YapDatabaseFullTextSearchBlockTypeWithMetadata  = 203,
	YapDatabaseFullTextSearchBlockTypeWithRow       = 204
} YapDatabaseFullTextSearchBlockType;

@interface YapDatabaseFullTextSearch : YapDatabaseExtension

/* Inherited from YapDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

- (id)initWithColumnNames:(NSArray *)columnNames
                    block:(YapDatabaseFullTextSearchBlock)block
                blockType:(YapDatabaseFullTextSearchBlockType)blockType;

- (id)initWithColumnNames:(NSArray *)columnNames
                    block:(YapDatabaseFullTextSearchBlock)block
                blockType:(YapDatabaseFullTextSearchBlockType)blockType
                  version:(int)version;

- (id)initWithColumnNames:(NSArray *)columnNames
                  options:(NSDictionary *)options
                    block:(YapDatabaseFullTextSearchBlock)block
                blockType:(YapDatabaseFullTextSearchBlockType)blockType
                  version:(int)version;

@property (nonatomic, strong, readonly) YapDatabaseFullTextSearchBlock block;
@property (nonatomic, assign, readonly) YapDatabaseFullTextSearchBlockType blockType;

/**
 * The version assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass an incremented version during the init method,
 * and the FTS extension will automatically update itself.
**/
@property (nonatomic, assign, readonly) int version;

@end
