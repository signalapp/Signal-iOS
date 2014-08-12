#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapDatabaseSecondaryIndexOptions.h"
#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

/**
 * Welcome to YapDatabase!
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseSecondaryIndex is an extension which allows you to add additional indexes for fast searching.
 *
 * That is, it allows you to create index(es) within sqlite for particular properties of your objects.
 * You can then issue queries to find or enumerate objects.
 * Examples:
 * 
 * - enumerate all people in the database where: age >= 62
 * - find the contact where: email == "johndoe@domain.com"
 *
 * For more information, see the wiki article about secondary indexes:
 * https://github.com/yaptv/YapDatabase/wiki/Secondary-Indexes
**/

/**
 * The block handles extracting the column values for the secondary indexes.
 *
 * When you add or update rows in the databse the block is invoked.
 * Your block can inspect the row and determine if it contains any values that should be added to the secondary indexes.
 * If not, the  block can simply return.
 * Otherwise the block should extract any values and add them to the given dictionary.
 *
 * After the block returns, the dictionary parameter will be inspected,
 * and any set values will be automatically inserted/updated within the sqlite indexes.
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The extension can make various optimizations based on required parameters of the block.
 * For example, if metadata isn't required, then the extension can ignore metadata-only updates.
**/
typedef id YapDatabaseSecondaryIndexBlock; // One of the YapDatabaseSecondaryIndexWith_X_Block types below.

typedef void (^YapDatabaseSecondaryIndexWithKeyBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key);
typedef void (^YapDatabaseSecondaryIndexWithObjectBlock)   \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object);
typedef void (^YapDatabaseSecondaryIndexWithMetadataBlock) \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id metadata);
typedef void (^YapDatabaseSecondaryIndexWithRowBlock)      \
                            (NSMutableDictionary *dict, NSString *collection, NSString *key, id object, id metadata);

/**
 * Use this enum to specify what kind of block you're passing.
**/
typedef NS_ENUM(NSInteger, YapDatabaseSecondaryIndexBlockType) {
	YapDatabaseSecondaryIndexBlockTypeWithKey       = 1031,
	YapDatabaseSecondaryIndexBlockTypeWithObject    = 1032,
	YapDatabaseSecondaryIndexBlockTypeWithMetadata  = 1033,
	YapDatabaseSecondaryIndexBlockTypeWithRow       = 1034
};


@interface YapDatabaseSecondaryIndex : YapDatabaseExtension

/* Inherited from YapDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

/**
 * Creates a new secondary index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 * 
 *   A YapDatabaseSecondaryIndexSetup instance allows you to specify the column names and type.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   The types can reflect numbers or text.
 * 
 * @param block
 * 
 *   Pass a block that is one of the following types:
 *    - YapDatabaseSecondaryIndexWithKeyBlock
 *    - YapDatabaseSecondaryIndexWithObjectBlock
 *    - YapDatabaseSecondaryIndexWithMetadataBlock
 *    - YapDatabaseSecondaryIndexWithRowBlock
 * 
 * @param blockType
 * 
 *   Pass the blockType enum that matches the passed block:
 *    - YapDatabaseSecondaryIndexBlockTypeWithKey
 *    - YapDatabaseSecondaryIndexBlockTypeWithObject
 *    - YapDatabaseSecondaryIndexBlockTypeWithMetadata
 *    - YapDatabaseSecondaryIndexBlockTypeWithRow
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
              block:(YapDatabaseSecondaryIndexBlock)block
          blockType:(YapDatabaseSecondaryIndexBlockType)blockType;

/**
 * Creates a new secondary index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 * 
 *   A YapDatabaseSecondaryIndexSetup instance allows you to specify the column names and type.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   The types can reflect numbers or text.
 * 
 * @param block
 * 
 *   Pass a block that is one of the following types:
 *    - YapDatabaseSecondaryIndexWithKeyBlock
 *    - YapDatabaseSecondaryIndexWithObjectBlock
 *    - YapDatabaseSecondaryIndexWithMetadataBlock
 *    - YapDatabaseSecondaryIndexWithRowBlock
 * 
 * @param blockType
 * 
 *   Pass the blockType enum that matches the passed block:
 *    - YapDatabaseSecondaryIndexBlockTypeWithKey
 *    - YapDatabaseSecondaryIndexBlockTypeWithObject
 *    - YapDatabaseSecondaryIndexBlockTypeWithMetadata
 *    - YapDatabaseSecondaryIndexBlockTypeWithRow
 * 
 * @param version
 * 
 *   If, after creating the secondary index(es), you need to change the setup or block,
 *   then simply increment the version parameter. If you pass a version that is different from the last
 *   initialization of the extension, then it will automatically re-create itself.
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
              block:(YapDatabaseSecondaryIndexBlock)block
          blockType:(YapDatabaseSecondaryIndexBlockType)blockType
         versionTag:(NSString *)versionTag;

/**
 * Creates a new secondary index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 * 
 *   A YapDatabaseSecondaryIndexSetup instance allows you to specify the column names and type.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   The types can reflect numbers or text.
 * 
 * @param block
 * 
 *   Pass a block that is one of the following types:
 *    - YapDatabaseSecondaryIndexWithKeyBlock
 *    - YapDatabaseSecondaryIndexWithObjectBlock
 *    - YapDatabaseSecondaryIndexWithMetadataBlock
 *    - YapDatabaseSecondaryIndexWithRowBlock
 * 
 * @param blockType
 * 
 *   Pass the blockType enum that matches the passed block:
 *    - YapDatabaseSecondaryIndexBlockTypeWithKey
 *    - YapDatabaseSecondaryIndexBlockTypeWithObject
 *    - YapDatabaseSecondaryIndexBlockTypeWithMetadata
 *    - YapDatabaseSecondaryIndexBlockTypeWithRow
 * 
 * @param version
 * 
 *   If, after creating the secondary index(es), you need to change the setup or block,
 *   then simply increment the version parameter. If you pass a version that is different from the last
 *   initialization of the extension, then it will automatically re-create itself.
 * 
 * @param options
 * 
 *   Allows you to specify extra options to configure the extension.
 *   See the YapDatabaseSecondaryIndexOptions class for more information.
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
              block:(YapDatabaseSecondaryIndexBlock)block
          blockType:(YapDatabaseSecondaryIndexBlockType)blockType
         versionTag:(NSString *)versionTag
            options:(YapDatabaseSecondaryIndexOptions *)options;

/**
 * The versionTag assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass a different versionTag during the init method,
 * and the extension will automatically update itself.
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

@end
