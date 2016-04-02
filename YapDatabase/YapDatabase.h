#import <Foundation/Foundation.h>

#import "YapDatabaseOptions.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"
#import "YapDatabaseExtension.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * The YapDatabase class is the top level class used to initialize the database.
 * It largely represents the immutable aspects of the database such as:
 *
 * - the filepath of the sqlite file
 * - the serializer and deserializer (for turning objects into data blobs, and back into objects again)
 *
 * To access or modify the database you create one or more connections to it.
 * Connections are thread-safe, and you can spawn multiple connections in order to achieve
 * concurrent access to the database from multiple threads.
 * You can even read from the database while writing to it from another connection on another thread.
**/

#if defined(SQLITE_HAS_CODEC) && defined(YAP_STANDARD_SQLITE)

	#error It seems you're using CocoaPods and you included YapDatabase and YapDatabase/Cipher pods. You just need to use "pod YapDatabase/SQLCipher"

#endif

/**
 * How does YapDatabase store my objects to disk?
 *
 * That question is answered extensively in the wiki article "Storing Objects":
 * https://github.com/yapstudios/YapDatabase/wiki/Storing-Objects
 *
 * Here's the intro from the wiki article:
 *
 * > In order to store an object to disk (via YapDatabase or any other protocol) you need some way of
 * > serializing the object. That is, convert the object into a big blob of bytes. And then, to get your
 * > object back from the disk you deserialize it (convert big blob of bytes back into object form).
 * >
 * > With YapDatabase, you can choose the default serialization/deserialization process,
 * > or you can customize it and use your own routines.
 *
 * In order to support adding objects to the database, serializers and deserializers are used.
 * The serializer and deserializer are just simple blocks that you can optionally configure.
 * The default serializer/deserializer uses NSCoding, so they are as simple and fast:
 *
 * defaultSerializer = ^(NSString *collection, NSString *key, id object){
 *     return [NSKeyedArchiver archivedDataWithRootObject:object];
 * };
 * defaultDeserializer = ^(NSString *collection, NSString *key, NSData *data) {
 *     return [NSKeyedUnarchiver unarchiveObjectWithData:data];
 * };
 *
 * If you use the initWithPath initializer, the default serializer/deserializer are used.
 * Thus to store objects in the database, the objects need only support the NSCoding protocol.
 * You may optionally use a custom serializer/deserializer for the objects and/or metadata.
**/
typedef NSData * __nonnull (^YapDatabaseSerializer)(NSString *collection, NSString *key, id object);
typedef id __nonnull (^YapDatabaseDeserializer)(NSString *collection, NSString *key, NSData *data);

/**
 * The sanitizer block allows you to enforce desired behavior of the objects you put into the database.
 *
 * If set, the sanitizer block will be run on all items being input into the database via
 * the setObject:forKey:inCollection: (and other setObject:XXX: methods).
 * 
 * You have 2 different hooks for running a sanitizer block:
 *
 * The PreSanitizer is run:
 * - Before the object is serialized
 * - Before the object is stored in the cache
 * - Before the object is passed to extensions
 * 
 * The PostSanitizer is run:
 * - After the object has been serialized
 * - After the object has been stored in the cache
 * - After the object has been passed to extensions
 *
 * The PreSanitizer is generally used validate the objects going into the database,
 * and/or to enforce immutability of those objects.
 *
 * Enforcing immutability is a topic covered in the "Object Policy" wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Object-Policy
 *
 * The PostSanitizer is generally used to "clear flags" that are used by extensions.
 * For example, your objects might have a "changedProperties" property that tells extensions exactly
 * what properties where changed on a modified object. And the extension uses that information
 * in order to automatically sync the changes to the cloud. Thus the PostSanitizer would be used
 * to clear the "changedProperties" after the extension has processed the modified object.
 * 
 * An example of such a use for the PostSanitizer is discussed in the YapDatabaseCloudKit wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit
**/
typedef id __nonnull (^YapDatabasePreSanitizer)(NSString *collection, NSString *key, id obj);
typedef void (^YapDatabasePostSanitizer)(NSString *collection, NSString *key, id obj);

/**
 * This notification is posted when a YapDatabase instance is deallocated,
 * and has thus closed all references to the underlying sqlite files.
 * 
 * If you intend to delete the sqlite file(s) from disk,
 * it's recommended you use this notification as a hook to do so.
 * 
 * More info:
 * The YapDatabase class itself is just a retainer for the filepath, blocks, config, etc.
 * And YapDatabaseConnection(s) open a sqlite connection to the database file,
 * and rely on the blocks & config in the parent YapDatabase class.
 * Thus a YapDatabaseConnection instance purposely retains the YapDatabase instance.
 * This means that in order to fully close all references to the underlying sqlite file(s),
 * you need to deallocate YapDatabase and all associated YapDatabaseConnections.
 * While this may be simple in concept, it's generally difficult to know exactly when all
 * the instances have been deallocated. Especially when there may be a bunch of asynchronous operations going.
 * 
 * Therefore the best approach is to do the following:
 * - destroy your YapDatabase instance (set it to nil)
 * - destroy all YapDatabaseConnection instances
 * - wait for YapDatabaseClosedNotification
 * - use notification as hook to delete all associated sqlite files from disk
 *
 * The userInfo dictionary will look like this:
 * @{
 *     YapDatabasePathKey    : <NSString of full filePath to db.sqlite file>,
 *     YapDatabasePathWalKey : <NSString of full filePath to db.sqlite-wal file>,
 *     YapDatabasePathShmKey : <NSString of full filePath to db.sqlite-shm file>,
 * }
 *
 * This notification is always posted to the main thread.
**/
extern NSString *const YapDatabaseClosedNotification;

extern NSString *const YapDatabasePathKey;
extern NSString *const YapDatabasePathWalKey;
extern NSString *const YapDatabasePathShmKey;

/**
 * This notification is posted following a readwrite transaction where the database was modified.
 * 
 * It is documented in more detail in the wiki article "YapDatabaseModifiedNotification":
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseModifiedNotification
 *
 * The notification object will be the database instance itself.
 * That is, it will be an instance of YapDatabase.
 *
 * This notification is only posted for internal modifications.
 * When the `enableMultiprocessSupport` option is set, external modification notifications are made
 * available by adding a `CrossProcessNotifier` extension to the database, and listening to the
 * `YapDatabaseModifiedExternallyNotification`.
 *
 * The userInfo dictionary will look something like this:
 * @{
 *     YapDatabaseSnapshotKey   : <NSNumber of snapshot, incremented per read-write transaction w/modification>,
 *     YapDatabaseConnectionKey : <YapDatabaseConnection instance that made the modification(s)>,
 *     YapDatabaseExtensionsKey : <NSDictionary with individual changeset info per extension>,
 *     YapDatabaseCustomKey     : <Optional object associated with this change, set by you>,
 * }
 *
 * This notification is always posted to the main thread.
**/
extern NSString *const YapDatabaseModifiedNotification;

/**
 * When the `enableMultiprocessSupport` option is set and a `CrossProcessNotifier` extension has been
 * added to the database, this notification is posted following a readwrite transaction where the
 * database was modified in another process.
 *
 * This notification is always posted to the main thread.
 **/
extern NSString *const YapDatabaseModifiedExternallyNotification;

extern NSString *const YapDatabaseSnapshotKey;
extern NSString *const YapDatabaseConnectionKey;
extern NSString *const YapDatabaseExtensionsKey;
extern NSString *const YapDatabaseCustomKey;

extern NSString *const YapDatabaseObjectChangesKey;
extern NSString *const YapDatabaseMetadataChangesKey;
extern NSString *const YapDatabaseRemovedKeysKey;
extern NSString *const YapDatabaseRemovedCollectionsKey;
extern NSString *const YapDatabaseAllKeysRemovedKey;
extern NSString *const YapDatabaseModifiedExternallyKey;


@interface YapDatabase : NSObject

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus any objects that support the NSCoding protocol may be used.
 *
 * Many of Apple's primary data types support NSCoding out of the box.
 * It's easy to add NSCoding support to your own custom objects.
**/
+ (YapDatabaseSerializer)defaultSerializer;
+ (YapDatabaseDeserializer)defaultDeserializer;

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively by Apple.
 *
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (YapDatabaseSerializer)propertyListSerializer;
+ (YapDatabaseDeserializer)propertyListDeserializer;

/**
 * A FASTER serializer & deserializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (YapDatabaseSerializer)timestampSerializer;
+ (YapDatabaseDeserializer)timestampDeserializer;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Opens or creates a sqlite database with the given path.
 * The defaults are used for everything.
 * 
 * In particular, the defaultSerializer and defaultDeserializer are used. (NSCoding)
 * No sanitizer is used.
 * The default options are used.
 *
 * @see defaultSerializer
 * @see defaultDeserializer
 * @see YapDatabaseOptions
 *
 * Example code:
 * 
 *   NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
 *   NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
 *   NSString *databasePath = [baseDir stringByAppendingPathComponent:@"myDatabase.sqlite"];
 * 
 *   YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
**/
- (id)initWithPath:(NSString *)path;

/**
 * Opens or creates a sqlite database with the given path.
 * The given options are used instead of the default options.
**/
- (id)initWithPath:(NSString *)path
           options:(nullable YapDatabaseOptions *)options;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
 * No sanitizer is used.
**/
- (id)initWithPath:(NSString *)path
        serializer:(nullable YapDatabaseSerializer)serializer
      deserializer:(nullable YapDatabaseDeserializer)deserializer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
 * The given options are used instead of the default options.
**/
- (id)initWithPath:(NSString *)path
        serializer:(nullable YapDatabaseSerializer)serializer
      deserializer:(nullable YapDatabaseDeserializer)deserializer
           options:(nullable YapDatabaseOptions *)options;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
 * The given sanitizer is used for both objects and metadata.
 * The given options are used instead of the default options.
**/
- (id)initWithPath:(NSString *)path
        serializer:(nullable YapDatabaseSerializer)serializer
      deserializer:(nullable YapDatabaseDeserializer)deserializer
      preSanitizer:(nullable YapDatabasePreSanitizer)preSanitizer
     postSanitizer:(nullable YapDatabasePostSanitizer)postSanitizer
           options:(nullable YapDatabaseOptions *)options;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
 * No sanitizer is used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(nullable YapDatabaseSerializer)objectSerializer
                                  objectDeserializer:(nullable YapDatabaseDeserializer)objectDeserializer
                                  metadataSerializer:(nullable YapDatabaseSerializer)metadataSerializer
                                metadataDeserializer:(nullable YapDatabaseDeserializer)metadataDeserializer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
 * The given sanitizers are used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(nullable YapDatabaseSerializer)objectSerializer
                                  objectDeserializer:(nullable YapDatabaseDeserializer)objectDeserializer
                                  metadataSerializer:(nullable YapDatabaseSerializer)metadataSerializer
                                metadataDeserializer:(nullable YapDatabaseDeserializer)metadataDeserializer
                                             options:(nullable YapDatabaseOptions *)options;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
 * The given sanitizers are used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(nullable YapDatabaseSerializer)objectSerializer
                                  objectDeserializer:(nullable YapDatabaseDeserializer)objectDeserializer
                                  metadataSerializer:(nullable YapDatabaseSerializer)metadataSerializer
                                metadataDeserializer:(nullable YapDatabaseDeserializer)metadataDeserializer
                                  objectPreSanitizer:(nullable YapDatabasePreSanitizer)objectPreSanitizer
                                 objectPostSanitizer:(nullable YapDatabasePostSanitizer)objectPostSanitizer
                                metadataPreSanitizer:(nullable YapDatabasePreSanitizer)metadataPreSanitizer
                               metadataPostSanitizer:(nullable YapDatabasePostSanitizer)metadataPostSanitizer
                                             options:(nullable YapDatabaseOptions *)options;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@property (nonatomic, strong, readonly) NSString *databasePath;
@property (nonatomic, strong, readonly) NSString *databasePath_wal;
@property (nonatomic, strong, readonly) NSString *databasePath_shm;

@property (nonatomic, copy, readonly) YapDatabaseSerializer objectSerializer;
@property (nonatomic, copy, readonly) YapDatabaseDeserializer objectDeserializer;

@property (nonatomic, copy, readonly) YapDatabaseSerializer metadataSerializer;
@property (nonatomic, copy, readonly) YapDatabaseDeserializer metadataDeserializer;

@property (nonatomic, copy, readonly, nullable) YapDatabasePreSanitizer objectPreSanitizer;
@property (nonatomic, copy, readonly, nullable) YapDatabasePostSanitizer objectPostSanitizer;

@property (nonatomic, copy, readonly, nullable) YapDatabasePreSanitizer metadataPreSanitizer;
@property (nonatomic, copy, readonly, nullable) YapDatabasePostSanitizer metadataPostSanitizer;

@property (nonatomic, copy, readonly) YapDatabaseOptions *options;

/**
 * The snapshot number is the internal synchronization state primitive for the database.
 * It's generally only useful for database internals,
 * but it can sometimes come in handy for general debugging of your app.
 *
 * The snapshot is a simple 64-bit number that gets incremented upon every readwrite transaction
 * that makes modifications to the database. Due to the concurrent architecture of YapDatabase,
 * there may be multiple concurrent connections that are inspecting the database at similar times,
 * yet they are looking at slightly different "snapshots" of the database.
 *
 * The snapshot number may thus be inspected to determine (in a general fashion) what state the connection
 * is in compared with other connections.
 *
 * YapDatabase.snapshot = most up-to-date snapshot among all connections
 * YapDatabaseConnection.snapshot = snapshot of individual connection
 *
 * Example:
 *
 * YapDatabase *database = [[YapDatabase alloc] init...];
 * database.snapshot; // returns zero
 *
 * YapDatabaseConnection *connection1 = [database newConnection];
 * YapDatabaseConnection *connection2 = [database newConnection];
 *
 * connection1.snapshot; // returns zero
 * connection2.snapshot; // returns zero
 *
 * [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *     [transaction setObject:objectA forKey:keyA];
 * }];
 *
 * database.snapshot;    // returns 1
 * connection1.snapshot; // returns 1
 * connection2.snapshot; // returns 1
 *
 * [connection1 asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *     [transaction setObject:objectB forKey:keyB];
 *     [NSThread sleepForTimeInterval:1.0]; // sleep for 1 second
 *
 *     connection1.snapshot; // returns 1 (we know it will turn into 2 once the transaction completes)
 * } completion:^{
 *
 *     connection1.snapshot; // returns 2
 * }];
 *
 * [connection2 asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){
 *     [NSThread sleepForTimeInterval:5.0]; // sleep for 5 seconds
 *
 *     connection2.snapshot; // returns 1. See why?
 * }];
 *
 * It's because connection2 started its transaction when the database was in snapshot 1.
 * Thus, for the duration of its transaction, the database remains in that state.
 *
 * However, once connection2 completes its transaction, it will automatically update itself to snapshot 2.
 *
 * In general, the snapshot is primarily for internal use.
 * However, it may come in handy for some tricky edge-case bugs (why doesn't my connection see that other commit?)
**/
@property (atomic, assign, readonly) uint64_t snapshot;

/**
 * Returns the version of sqlite being used.
 *
 * E.g.: SELECT sqlite_version();
**/
@property (atomic, readonly) NSString *sqliteVersion;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Defaults
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Allows you to set the default objectCacheEnabled and objectCacheLimit for all new connections.
 *
 * When you create a connection via [database newConnection], that new connection will inherit
 * its initial configuration via the default values configured for the parent database.
 * Of course, the connection may then override these default configuration values, and configure itself as needed.
 *
 * Changing the default values only affects future connections that will be created.
 * It does not affect connections that have already been created.
 *
 * The default defaultObjectCacheEnabled is YES.
 * The default defaultObjectCacheLimit is 250.
 *
 * For more detailed documentation on these properties, see the YapDatabaseConnection header file.
 * @see YapDatabaseConnection objectCacheEnabled
 * @see YapDatabaseConnection objectCacheLimit
**/
@property (atomic, assign, readwrite) BOOL defaultObjectCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger defaultObjectCacheLimit;

/**
 * Allows you to set the default metadataCacheEnabled and metadataCacheLimit for all new connections.
 *
 * When you create a connection via [database newConnection], that new connection will inherit
 * its initial configuration via the default values configured for the parent database.
 * Of course, the connection may then override these default configuration values, and configure itself as needed.
 *
 * Changing the default values only affects future connections that will be created.
 * It does not affect connections that have already been created.
 *
 * The default defaultMetadataCacheEnabled is YES.
 * The default defaultMetadataCacheLimit is 500.
 *
 * For more detailed documentation on these properties, see the YapDatabaseConnection header file.
 * @see YapDatabaseConnection metadataCacheEnabled
 * @see YapDatabaseConnection metadataCacheLimit
**/
@property (atomic, assign, readwrite) BOOL defaultMetadataCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger defaultMetadataCacheLimit;

/**
 * Allows you to set the default objectPolicy and metadataPolicy for all new connections.
 * 
 * When you create a connection via [database newConnection], that new connection will inherit
 * its initial configuration via the default values configured for the parent database.
 * Of course, the connection may then override these default configuration values, and configure itself as needed.
 *
 * Changing the default values only affects future connections that will be created.
 * It does not affect connections that have already been created.
 * 
 * The default defaultObjectPolicy is YapDatabasePolicyContainment.
 * The default defaultMetadataPolicy is YapDatabasePolicyContainment.
 * 
 * For more detailed documentation on these properties, see the YapDatabaseConnection header file.
 * @see YapDatabaseConnection objectPolicy
 * @see YapDatabaseConnection metadataPolicy
**/
@property (atomic, assign, readwrite) YapDatabasePolicy defaultObjectPolicy;
@property (atomic, assign, readwrite) YapDatabasePolicy defaultMetadataPolicy;

#if TARGET_OS_IPHONE
/**
 * Allows you to set the default autoFlushMemoryFlags for all new connections.
 *
 * When you create a connection via [database newConnection], that new connection will inherit
 * its initial configuration via the default values configured for the parent database.
 * Of course, the connection may then override these default configuration values, and configure itself as needed.
 *
 * Changing the default values only affects future connections that will be created.
 * It does not affect connections that have already been created.
 * 
 * The default defaultAutoFlushMemoryFlags is YapDatabaseConnectionFlushMemoryFlags_All.
 *
 * For more detailed documentation on these properties, see the YapDatabaseConnection header file.
 * @see YapDatabaseConnection autoFlushMemoryFlags
**/
@property (atomic, assign, readwrite) YapDatabaseConnectionFlushMemoryFlags defaultAutoFlushMemoryFlags;
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Creates and returns a new connection to the database.
 * It is through this connection that you will access the database.
 * 
 * You can create multiple connections to the database.
 * Each invocation of this method creates and returns a new connection.
 * 
 * Multiple connections can simultaneously read from the database.
 * Multiple connections can simultaneously read from the database while another connection is modifying the database.
 * For example, the main thread could be reading from the database via connection A,
 * while a background thread is writing to the database via connection B.
 * 
 * However, only a single connection may be writing to the database at any one time.
 *
 * A connection is thread-safe, and operates by serializing access to itself.
 * Thus you can share a single connection between multiple threads.
 * But for conncurrent access between multiple threads you must use multiple connections.
 *
 * You should avoid creating more connections than you need.
 * Creating a new connection everytime you need to access the database is a recipe for foolishness.
**/
- (YapDatabaseConnection *)newConnection;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to a (synchronous) readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 *
 * @param extension
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 * 
 * @param extensionName
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @return
 *     YES if the extension was properly registered.
 *     NO if an error occurred, such as the extensionName is already registered.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionQueue:completionBlock:
**/
- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;

/**
 * Registers the extension with the database using the given name.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to a (synchronous) readwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     This allows you to control things such as the cache size of the connection that performs
 *     the extension registration code (sometimes important for performance tuning.)
 *     If you pass nil, an internal databaseConnection will automatically be used.
 * 
 * @see asyncRegisterExtension:withName:completionBlock:
 * @see asyncRegisterExtension:withName:completionQueue:completionBlock:
**/
- (BOOL)registerExtension:(YapDatabaseExtension *)extension
                 withName:(NSString *)extensionName
               connection:(nullable YapDatabaseConnection *)connection;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 * 
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
					  withName:(NSString *)extensionName
			   completionBlock:(nullable void(^)(BOOL ready))completionBlock;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionQueue:(nullable dispatch_queue_t)completionQueue
               completionBlock:(nullable void(^)(BOOL ready))completionBlock;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     This allows you to control things such as the cache size of the connection that performs
 *     the extension registration code (sometimes important for performance tuning.)
 *     If you pass nil, an internal databaseConnection will automatically be used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                    connection:(nullable YapDatabaseConnection *)connection
               completionBlock:(nullable void(^)(BOOL ready))completionBlock;

/**
 * Asynchronoulsy starts the extension registration process.
 * After registration everything works automatically using just the extension name.
 *
 * The registration process is equivalent to an asyncReadwrite transaction.
 * It involves persisting various information about the extension to the database,
 * as well as possibly populating the extension by enumerating existing rows in the database.
 * 
 * @param extension (required)
 *     The YapDatabaseExtension subclass instance you wish to register.
 *     For example, this might be a YapDatabaseView instance.
 *
 * @param extensionName (required)
 *     This is an arbitrary string you assign to the extension.
 *     Once registered, you will generally access the extension instance via this name.
 *     For example: [[transaction ext:@"myView"] numberOfGroups];
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     This allows you to control things such as the cache size of the connection that performs
 *     the extension registration code (sometimes important for performance tuning.)
 *     If you pass nil, an internal databaseConnection will automatically be used.
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     If the extension registration was successful then the ready parameter will be YES.
**/
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                    connection:(nullable YapDatabaseConnection *)connection
               completionQueue:(nullable dispatch_queue_t)completionQueue
               completionBlock:(nullable void(^)(BOOL ready))completionBlock;

/**
 * This method unregisters an extension with the given name.
 * The associated underlying tables will be dropped from the database.
 * 
 * The unregistration process is equivalent to a (synchronous) readwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 *
 * Note 1:
 *   You don't need to re-register an extension in order to unregister it. For example,
 *   you've previously registered an extension (in previous app launches), but you no longer need the extension.
 *   You don't have to bother creating and registering the unneeded extension,
 *   just so you can unregister it and have the associated tables dropped.
 *   The database persists information about registered extensions, including the associated class of an extension.
 *   So you can simply pass the name of the extension, and the database system will use the associated class to
 *   drop the appropriate tables.
 *
 * Note 2:
 *   In fact, you don't even have to worry about unregistering extensions that you no longer need.
 *   That database system will automatically handle it for you.
 *   That is, upon completion of the first readWrite transaction (that makes changes), the database system will
 *   check to see if there are any "orphaned" extensions. That is, previously registered extensions that are
 *   no longer in use (and are now out-of-date because they didn't process the recent change(s) to the db).
 *   And it will automatically unregister these orhpaned extensions for you.
 *       
 * @see asyncUnregisterExtensionWithName:completionBlock:
 * @see asyncUnregisterExtensionWithName:completionQueue:completionBlock:
**/
- (void)unregisterExtensionWithName:(NSString *)extensionName;

/**
 * This method unregisters an extension with the given name.
 * The associated underlying tables will be dropped from the database.
 *
 * The unregistration process is equivalent to a (synchronous) readwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     If you pass nil, an internal databaseConnection will automatically be used.
**/
- (void)unregisterExtensionWithName:(NSString *)extensionName connection:(nullable YapDatabaseConnection *)connection;

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 * 
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                         completionBlock:(nullable dispatch_block_t)completionBlock;

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 * 
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(nullable dispatch_block_t)completionBlock;

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     If you pass nil, an internal databaseConnection will automatically be used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
 *     The completionBlock will be invoked on the main thread (dispatch_get_main_queue()).
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                              connection:(nullable YapDatabaseConnection *)connection
                         completionBlock:(nullable dispatch_block_t)completionBlock;

/**
 * Asynchronoulsy starts the extension unregistration process.
 *
 * The unregistration process is equivalent to an asyncReadwrite transaction.
 * It involves deleting various information about the extension from the database,
 * as well as possibly dropping related tables the extension may have been using.
 *
 * @param extensionName (required)
 *     This is the arbitrary string you assigned to the extension when you registered it.
 * 
 * @param connection (optional)
 *     You may optionally pass your own databaseConnection for this method to use.
 *     If you pass nil, an internal databaseConnection will automatically be used.
 *
 * @param completionQueue (optional)
 *     The dispatch_queue to invoke the completion block may optionally be specified.
 *     If NULL, dispatch_get_main_queue() is automatically used.
 *
 * @param completionBlock (optional)
 *     An optional completion block may be used.
**/
- (void)asyncUnregisterExtensionWithName:(NSString *)extensionName
                              connection:(nullable YapDatabaseConnection *)connection
                         completionQueue:(nullable dispatch_queue_t)completionQueue
                         completionBlock:(nullable dispatch_block_t)completionBlock;

/**
 * Returns the registered extension with the given name.
 * The returned object will be a subclass of YapDatabaseExtension.
**/
- (nullable id)registeredExtension:(NSString *)extensionName;

/**
 * Returns all currently registered extensions as a dictionary.
 * The key is the registed name (NSString), and the value is the extension (YapDatabaseExtension subclass).
**/
- (nullable NSDictionary *)registeredExtensions;

/**
 * Allows you to fetch the registered extension names from the last time the database was run.
 * Typically this means from the last time the app was run.
 * 
 * This may be used to assist in various tasks, such as cleanup or upgrade tasks.
 * 
 * If you need this information, you should fetch it early on because YapDatabase only maintains this information
 * until it sees you are done registering all your initial extensions. That is, after one initializes the database
 * they then immediately register any needed initial extensions before they begin to use the database. Once a 
 * readWriteTransaction modifies the database, YapDatabase will take this opportunity to look for orphaned extensions.
 * These are extensions that were registered at the end of the last database session,
 * but which are no longer registered. YapDatabase will automatically cleanup these orphaned extensions,
 * and also clear the previouslyRegisteredExtensionNames information at this point.
**/
- (nullable NSArray<NSString *> *)previouslyRegisteredExtensionNames;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connection Pooling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * As recommended in the "Performance Primer" ( https://github.com/yapstudios/YapDatabase/wiki/Performance-Primer )
 * 
 * > You should consider connections to be relatively heavy weight objects.
 * >
 * > OK, truth be told they're not really that heavy weight. I'm just trying to scare you.
 * > Because in terms of performance, you get a lot of bang for your buck if you recycle your connections.
 *
 * However, experience has shown how easy it is to neglect this information.
 * Perhaps because it's just so darn easy to create a connection that it becomes easy to forgot
 * that connections aren't free.
 * 
 * Whatever the reason, the connection pool was designed to alleviate some of the overhead.
 * The most expensive component of a connection is the internal sqlite database connection.
 * The connection pool keeps these internal sqlite database connections around in a pool to help recycle them.
 *
 * So when a connection gets deallocated, it returns the sqlite database connection to the pool.
 * And when a new connection gets created, it can recycle a sqlite database connection from the pool.
 * 
 * This property sets a maximum limit on the number of items that will get stored in the pool at any one time.
 * 
 * The default value is 5.
 * 
 * See also connectionPoolLifetime,
 * which allows you to set a maximum lifetime of connections sitting around in the pool.
**/
@property (atomic, assign, readwrite) NSUInteger maxConnectionPoolCount;

/**
 * The connection pool can automatically drop "stale" connections.
 * That is, if an item stays in the pool for too long (without another connection coming along and
 * removing it from the pool to be recycled) then the connection can optionally be removed and dropped.
 *
 * This is called the connection "lifetime".
 * 
 * That is, after an item is added to the connection pool to be recycled, a timer will be started.
 * If the connection is still in the pool when the timer goes off,
 * then the connection will automatically be removed and dropped.
 *
 * The default value is 90 seconds.
 * 
 * To disable the timer, set the lifetime to zero (or any non-positive value).
 * When disabled, open connections will remain in the pool indefinitely.
**/
@property (atomic, assign, readwrite) NSTimeInterval connectionPoolLifetime;

@end

NS_ASSUME_NONNULL_END
