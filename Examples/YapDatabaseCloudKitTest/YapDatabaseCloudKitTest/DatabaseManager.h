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
extern NSString *const Collection_Prefs;

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
 * The root database class.
**/
@property (nonatomic, strong, readonly) YapDatabase *database;

@end
