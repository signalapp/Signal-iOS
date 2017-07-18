#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseRTreeIndexSetup.h"
#import "YapDatabaseRTreeIndexHandler.h"
#import "YapDatabaseRTreeIndexOptions.h"
#import "YapDatabaseRTreeIndexConnection.h"
#import "YapDatabaseRTreeIndexTransaction.h"

/**
 * Welcome to YapDatabase!
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseRTreeIndex is an extension which allows you to add an additional geometrical index for fast searching.
 *
 * That is, it allows you to create an index within sqlite for geometrical properties of your objects.
 * You can then issue queries to find or enumerate objects.
 * Examples:
 *
 * - enumerate all people in a bounding-box
 * - enumerate all regions overlapping a bounding-box
 *
 * Note:
 *
 * The sqlite3 r-tree documentation <https://www.sqlite.org/rtree.html> states that
 *
 * > By default, coordinates are stored in an RTree using 32-bit floating point values. When a coordinate cannot be exactly represented by a 32-bit floating point number, the lower-bound coordinates are rounded down and the upper-bound coordinates are rounded up. Thus, bounding boxes might be slightly larger than specified, but will never be any smaller. This is exactly what is desired for doing the more common "overlapping" queries where the application wants to find every entry in the RTree that overlaps a query bounding box. Rounding the entry bounding boxes outward might cause a few extra entries to appears in an overlapping query if the edge of the entry bounding box corresponds to an edge of the query bounding box. But the overlapping query will never miss a valid table entry.
 *
 * so coordinates in the r-tree might differ slightly from the ones you are giving the app, in particular if you are using Double values.
 *
 * For more information, see the wiki article about rtree indexes:
 * https://github.com/yapstudios/YapDatabase/wiki/RTree-Indexes
**/
@interface YapDatabaseRTreeIndex : YapDatabaseExtension

/**
 * Creates a new rtree index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 *   A YapDatabaseRTreeIndexSetup instance allows you to specify the column names.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   Sqlite rtrees require that your columns must be a even list, each pair corresponding to a dimension
 *   of your geometrical index (eg. ["minX", "maxX", "minY", "maxY"]). Sqlite allows the dimension to vary
 *   between 1 and 5.
 *
 * @param handler
 *   The block (and blockType) that handles extracting rtree index information from a row in the database.
 *
 *
 * @see YapDatabaseRTreeIndexSetup
 * @see YapDatabaseRTreeIndexHandler
 *
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)setup
            handler:(YapDatabaseRTreeIndexHandler *)handler;

/**
 * Creates a new rtree index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 *   A YapDatabaseRTreeIndexSetup instance allows you to specify the column names.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   Sqlite rtrees require that your columns must be a even list, each pair corresponding to a dimension
 *   of your geometrical index (eg. ["minX", "maxX", "minY", "maxY"]). Sqlite allows the dimension to vary
 *   between 1 and 5.
 *
 * @param handler
 *   The block (and blockType) that handles extracting secondary index information from a row in the database.
 *
 * @param versionTag
 *   If, after creating the rtree index, you need to change the setup or block,
 *   then simply increment the version parameter. If you pass a version that is different from the last
 *   initialization of the extension, then it will automatically re-create itself.
 *
 * @see YapDatabaseRTreeIndexSetup
 * @see YapDatabaseRTreeIndexHandler
 *
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)setup
            handler:(YapDatabaseRTreeIndexHandler *)handler
         versionTag:(NSString *)versionTag;

/**
 * Creates a new rtree index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 *   A YapDatabaseRTreeIndexSetup instance allows you to specify the column names.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   Sqlite rtrees require that your columns must be a even list, each pair corresponding to a dimension
 *   of your geometrical index (eg. ["minX", "maxX", "minY", "maxY"]). Sqlite allows the dimension to vary
 *   between 1 and 5.
 *
 * @param handler
 *   The block (and blockType) that handles extracting secondary index information from a row in the database.
 *
 * @param versionTag
 *   If, after creating the rtree index, you need to change the setup or block,
 *   then simply increment the version parameter. If you pass a version that is different from the last
 *   initialization of the extension, then it will automatically re-create itself.
 *
 * @param options
 *   Allows you to specify extra options to configure the extension.
 *   See the YapDatabaseRTreeIndexOptions class for more information.
 *
 * @see YapDatabaseRTreeIndexSetup
 * @see YapDatabaseRTreeIndexHandler
 *
 * @see YapDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseRTreeIndexSetup *)setup
            handler:(YapDatabaseRTreeIndexHandler *)handler
         versionTag:(NSString *)versionTag
            options:(YapDatabaseRTreeIndexOptions *)options;


/* Inherited from YapDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

@property (nonatomic, copy, readonly) YapDatabaseRTreeIndexSetup *setup;
@property (nonatomic, strong, readonly) YapDatabaseRTreeIndexHandler *handler;

/**
 * The versionTag assists in making changes to the extension.
 *
 * If you need to change the columnNames and/or block,
 * then simply pass a different versionTag during the init method,
 * and the extension will automatically update itself.
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

@end
