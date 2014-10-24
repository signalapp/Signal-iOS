#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseCloudKit.h"

@class DatabaseManager;

/**
 * You can use this as an alternative to the sharedInstance:
 * [[DatabaseManager sharedInstance] uiDatabaseConnection] -> STDatabaseManager.uiDatabaseConnection
**/
extern DatabaseManager *MyDatabaseManager;

/**
 * The following constants are the database collection names.
 *
 * E.g.: [transaction objectForKey:todoId inCollection:Collection_Todos]
**/
extern NSString *const Collection_Todos;
extern NSString *const Collection_CloudKit;

/**
 * The following constants are the database extension names.
 *
 * E.g.: [[transaction ext:Ext_View_Order] objectAtIndexPath:indexPath withMappings:mappings]
**/
extern NSString *const Ext_View_Order;
extern NSString *const Ext_CloudKit;

/**
 * The following constants are the CloudKit zone names.
**/
extern NSString *const CloudKitZoneName;


@interface DatabaseManager : NSObject

/**
 * Standard singleton pattern.
 * As a shortcut, you can use the global MyDatabaseManager ivar instead.
**/
+ (instancetype)sharedInstance; // Or MyDatabaseManager global ivar

/**
 * The path of the raw database file.
**/
+ (NSString *)databasePath;

/**
 * The root database class, and extension(s)
**/
@property (nonatomic, strong, readonly) YapDatabase *database;
@property (nonatomic, strong, readonly) YapDatabaseCloudKit *cloudKitExtension;

/**
 * The databaseConnection for the main thread.
 * Will throw an exception if:
 * - you attempt to use it on a background thread (as that would block a read on the main thread)
 * - you attempt an async transaction (as that could also block a later read on the main thread)
**/
@property (nonatomic, strong, readonly) YapDatabaseConnection *uiDatabaseConnection;

/**
 * A generic databaseConnection for other asynchronous & background stuff.
**/
@property (nonatomic, strong, readonly) YapDatabaseConnection *bgDatabaseConnection;

@end
