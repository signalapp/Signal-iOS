#import <Foundation/Foundation.h>

#import "YapAbstractDatabase.h"

#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
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

/**
 * How does YapDatabase store my objects to disk?
 *
 * That question is answered extensively in the wiki article "Storing Objects":
 * https://github.com/yaptv/YapDatabase/wiki/Storing-Objects
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
 * If you use the initWithPath initializer, the default serializer/deserializer (above) are used.
 * Thus to store objects in the database, the objects need only support the NSCoding protocol.
 * You may optionally use a custom serializer/deserializer for the objects and/or metadata.
**/
typedef NSData* (^YapDatabaseSerializer)(NSString *collection, NSString *key, id object);
typedef id (^YapDatabaseDeserializer)(NSString *collection, NSString *key, NSData *data);

/**
 * Is it safe to store mutable objects in the database?
 *
 * That question is answered extensively in the wiki article "Thread Safety":
 * https://github.com/yaptv/YapDatabase/wiki/Thread-Safety
 *
 * The sanitizer block can be run on all objects as they are being input into the database.
 * That is, it will be run on all objects passed to setObject:forKey:inCollection: before
 * being handed to the database internals.
**/
typedef id (^YapDatabaseSanitizer)(NSString *collection, NSString *key, id object);


extern NSString *const YapDatabaseObjectChangesKey;
extern NSString *const YapDatabaseMetadataChangesKey;
extern NSString *const YapDatabaseRemovedKeysKey;
extern NSString *const YapDatabaseRemovedCollectionsKey;
extern NSString *const YapDatabaseAllKeysRemovedKey;


@interface YapDatabase : YapAbstractDatabase

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

#pragma mark Init

/**
 * Opens or creates a sqlite database with the given path.
 * The default serializer and deserializer are used.
 * No sanitizer is used.
 *
 * @see defaultSerializer
 * @see defaultDeserializer
**/
- (id)initWithPath:(NSString *)path;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
 * No sanitizer is used.
**/
- (id)initWithPath:(NSString *)path
        serializer:(YapDatabaseSerializer)serializer
      deserializer:(YapDatabaseDeserializer)deserializer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
 * The given sanitizer is used for both objects and metadata.
**/
- (id)initWithPath:(NSString *)path
        serializer:(YapDatabaseSerializer)serializer
      deserializer:(YapDatabaseDeserializer)deserializer
         sanitizer:(YapDatabaseSanitizer)sanitizer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
 * No sanitizer is used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(YapDatabaseSerializer)objectSerializer
                                  objectDeserializer:(YapDatabaseDeserializer)objectDeserializer
                                  metadataSerializer:(YapDatabaseSerializer)metadataSerializer
                                metadataDeserializer:(YapDatabaseDeserializer)metadataDeserializer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
 * The given sanitizers are used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(YapDatabaseSerializer)objectSerializer
                                  objectDeserializer:(YapDatabaseDeserializer)objectDeserializer
                                  metadataSerializer:(YapDatabaseSerializer)metadataSerializer
                                metadataDeserializer:(YapDatabaseDeserializer)metadataDeserializer
                                     objectSanitizer:(YapDatabaseSanitizer)objectSanitizer
                                   metadataSanitizer:(YapDatabaseSanitizer)metadataSanitizer;

#pragma mark Properties

@property (nonatomic, strong, readonly) YapDatabaseSerializer objectSerializer;
@property (nonatomic, strong, readonly) YapDatabaseDeserializer objectDeserializer;

@property (nonatomic, strong, readonly) YapDatabaseSerializer metadataSerializer;
@property (nonatomic, strong, readonly) YapDatabaseDeserializer metadataDeserializer;

@property (nonatomic, strong, readonly) YapDatabaseSanitizer objectSanitizer;
@property (nonatomic, strong, readonly) YapDatabaseSanitizer metadataSanitizer;

#pragma mark Connections

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

@end
