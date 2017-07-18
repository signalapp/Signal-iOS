#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseSecondaryIndexSetup.h"
#import "YapDatabaseSecondaryIndexHandler.h"
#import "YapDatabaseSecondaryIndexOptions.h"
#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
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
 * https://github.com/yapstudios/YapDatabase/wiki/Secondary-Indexes
**/
@interface YapDatabaseSecondaryIndex : YapDatabaseExtension

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
 * @param handler
 * 
 *   The block (and blockType) that handles extracting secondary index information from a row in the database.
 *
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapDatabaseSecondaryIndexHandler
 * 
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
            handler:(YapDatabaseSecondaryIndexHandler *)handler;

/**
 * Creates a new secondary index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 *   A YapDatabaseSecondaryIndexSetup instance allows you to specify the column names and type.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   The types can reflect numbers or text.
 * 
 * @param handler
 *   The block (and blockType) that handles extracting secondary index information from a row in the database.
 * 
 * @param versionTag
 *   If, after creating the secondary index(es), you need to change the setup or block,
 *   then simply increment the version parameter. If you pass a version that is different from the last
 *   initialization of the extension, then it will automatically re-create itself.
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapDatabaseSecondaryIndexHandler
 *
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
            handler:(YapDatabaseSecondaryIndexHandler *)handler
         versionTag:(nullable NSString *)versionTag;

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
 * @param handler
 * 
 *   The block (and blockType) that handles extracting secondary index information from a row in the database.
 * 
 * @param versionTag
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
 * @see YapDatabaseSecondaryIndexHandler
 *
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
            handler:(YapDatabaseSecondaryIndexHandler *)handler
         versionTag:(nullable NSString *)versionTag
            options:(nullable YapDatabaseSecondaryIndexOptions *)options;


/* Inherited from YapDatabaseExtension
 
@property (nonatomic, strong, readonly) NSString *registeredName;
 
*/

/**
 * The versionTag assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass a different versionTag during the init method,
 * and the extension will automatically update itself.
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

@end

NS_ASSUME_NONNULL_END
