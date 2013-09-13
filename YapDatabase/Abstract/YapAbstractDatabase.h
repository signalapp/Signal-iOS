#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtension.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * This is the base database class which is shared by YapDatabase and YapCollectionsDatabase.
 *
 * - YapDatabase = Key/Value
 * - YapCollectionsDatabase = Collection/Key/Value
 * 
 * You do not directly create instances of YapAbstractDatabase.
 * You instead create instances of YapDatabase or YapCollectionsDatabase.
 * Both YapDatabase and YapCollectionsDatabase extend YapAbstractDatabase.
 * 
 * YapAbstractDatabase provides the generic implementation of a database such as:
 * - common properties
 * - common initializers
 * - common setup code
 * - stub methods which are overriden by the subclasses
 * 
 * @see YapDatabase.h
 * @see YapCollectionsDatabase.h
**/

/**
 * This notification is posted following a readwrite transaction where the database was modified.
 *
 * The notification object will be the database instance itself.
 * That is, it will be an instance of YapDatabase or YapCollectionsDatabase.
 * 
 * The userInfo dictionary will look something like this:
 * @{
 *     YapDatabaseSnapshotKey = <NSNumber of snapshot, incremented per read-write transaction w/modification>,
 *     YapDatabaseConnectionKey = <YapDatabaseConnection instance that made the modification(s)>,
 *     YapDatabaseExtensionsKey = <NSDictionary with individual changeset info per extension>,
 *     YapDatabaseCustomKey = <Optional object associated with this change, set by you>,
 * }
 * 
 * This notification is always posted to the main thread.
**/
extern NSString *const YapDatabaseModifiedNotification;

extern NSString *const YapDatabaseSnapshotKey;
extern NSString *const YapDatabaseConnectionKey;
extern NSString *const YapDatabaseExtensionsKey;
extern NSString *const YapDatabaseCustomKey;


@interface YapAbstractDatabase : NSObject

/**
 * Opens or creates a sqlite database with the given path.
**/
- (id)initWithPath:(NSString *)path;

#pragma mark Properties

@property (nonatomic, strong, readonly) NSString *databasePath;

@property (atomic, assign, readonly) uint64_t snapshot;

#pragma mark Extensions

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 *
 * @return
 *     YES if the extension was properly registered.
 *     NO if an error occurred, such as the extensionName is already registered.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionBlock:completionQueue:
**/
- (BOOL)registerExtension:(YapAbstractDatabaseExtension *)extension withName:(NSString *)extensionName;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * An optional completion block may be used.
 * If the extension registration was successful then the ready parameter will be YES.
 *
 * The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapAbstractDatabaseExtension *)extension
					  withName:(NSString *)extensionName
			   completionBlock:(void(^)(BOOL ready))completionBlock;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to a readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * An optional completion block may be used.
 * If the extension registration was successful then the ready parameter will be YES.
 * 
 * Additionally the dispatch_queue to invoke the completion block may also be specified.
 * If NULL, dispatch_get_main_queue() is automatically used.
**/
- (void)asyncRegisterExtension:(YapAbstractDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(void(^)(BOOL ready))completionBlock
               completionQueue:(dispatch_queue_t)completionQueue;

/**
 * This method unregisters an extension with the given name.
 * The associated underlying tables will be dropped from the database.
 * 
 * Note 1:
 * You can unregister an extension that was hasn't been registered. For example,
 * you've previously registered an extension (in previous app launches), but you no longer need the extension.
 * You don't have to bother creating and registering the unneeded extension,
 * just so you can unregister it and have the associated tables dropped.
 * The database persists information about registered extensions, including the associated class of an extension.
 * So you can simply pass the name of the extension, and the database system will use the associated class to
 * drop the appropriate tables.
 *
 * Note:
 * You don't have to worry about unregistering extensions that you no longer need.
 *       
 * @see asyncUnregisterExtension:completionBlock:
 * @see asyncUnregisterExtension:completionBlock:completionQueue:
**/
- (void)unregisterExtension:(NSString *)extensionName;

/**
 * 
**/
- (void)asyncUnregisterExtension:(NSString *)extensionName
                 completionBlock:(dispatch_block_t)completionBlock;

- (void)asyncUnregisterExtension:(NSString *)extensionName
                 completionBlock:(dispatch_block_t)completionBlock
                 completionQueue:(dispatch_queue_t)completionQueue;

/**
 * Returns the registered extension with the given name.
 * The returned object will be a subclass of YapAbstractDatabaseExtension.
**/
- (id)registeredExtension:(NSString *)extensionName;

/**
 * Returns all currently registered extensions as a dictionary.
 * The key is the registed name (NSString), and the value is the extension (YapAbstractDatabaseExtension subclass).
**/
- (NSDictionary *)registeredExtensions;

@end
