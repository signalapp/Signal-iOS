#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtension.h"
#import "YapCollectionsDatabaseFullTextSearchConnection.h"
#import "YapCollectionsDatabaseFullTextSearchTransaction.h"

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
typedef id YapCollectionsDatabaseFullTextSearchBlock; // One of YapCollectionsDatabaseFullTextSearchXBlock types

typedef void (^YapCollectionsDatabaseFullTextSearchWithKeyBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);
typedef void (^YapCollectionsDatabaseFullTextSearchWithObjectBlock)   \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);
typedef void (^YapCollectionsDatabaseFullTextSearchWithMetadataBlock) \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id metadata);
typedef void (^YapCollectionsDatabaseFullTextSearchWithRowBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, id metadata);

/**
 * Use this enum to specify what kind of block you're passing.
**/
typedef enum {
	YapCollectionsDatabaseFullTextSearchBlockTypeWithKey       = 201,
	YapCollectionsDatabaseFullTextSearchBlockTypeWithObject    = 202,
	YapCollectionsDatabaseFullTextSearchBlockTypeWithMetadata  = 203,
	YapCollectionsDatabaseFullTextSearchBlockTypeWithRow       = 204
} YapCollectionsDatabaseFullTextSearchBlockType;

@interface YapCollectionsDatabaseFullTextSearch : YapAbstractDatabaseExtension

/* Inherited from YapAbstractDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

- (id)initWithColumnNames:(NSArray *)columnNames
                    block:(YapCollectionsDatabaseFullTextSearchBlock)block
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)blockType;

- (id)initWithColumnNames:(NSArray *)columnNames
                    block:(YapCollectionsDatabaseFullTextSearchBlock)block
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)blockType
                  version:(int)version;

- (id)initWithColumnNames:(NSArray *)columnNames
                  options:(NSDictionary *)options
                    block:(YapCollectionsDatabaseFullTextSearchBlock)block
                blockType:(YapCollectionsDatabaseFullTextSearchBlockType)blockType
                  version:(int)version;

@property (nonatomic, strong, readonly) YapCollectionsDatabaseFullTextSearchBlock block;
@property (nonatomic, assign, readonly) YapCollectionsDatabaseFullTextSearchBlockType blockType;

/**
 * The version assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass an incremented version during the init method,
 * and the FTS extension will automatically update itself.
**/
@property (nonatomic, assign, readonly) int version;

@end
