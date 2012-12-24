#import <Foundation/Foundation.h>

#import "YapAbstractDatabase.h"

#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

/**
 * YapDatabase provides concurrent thread-safe access to a key-value database backed by sqlite.
 * 
 * The keys are just plain strings.
 * The values are just plain objects.
 *
 * In order to support adding objects to the database, serializers and deserializers are used.
 * The default serializer/deserializer use NSCoding, so they are as simple and fast:
 * 
 * defaultSerializer = ^(id object){
 *     return [NSKeyedArchiver archivedDataWithRootObject:object];
 * };
 * defaultDeserializer = ^(NSData *data) {
 *     return [NSKeyedUnarchiver unarchiveObjectWithData:data];
 * };
 * 
 * If you use the initWithPath initializer, the default serializer/deserializer (above) are used.
 * Thus to store objects in the database, the objects need only support the NSCoding protocol.
 * You may optionally use a custom serializer/deserializer for the objects and/or metadata.
 * 
 * To access or modify the database you create one or more connections to it.
 * Connections are thread-safe, and you can spawn multiple connections in order to achieve
 * concurrent access to the database from multiple threads.
 * You can even read from the database while writing to it from another connection on another thread.
**/
@interface YapDatabase : YapAbstractDatabase

/* Inherited from YapAbstractDatabase

+ (NSData *(^)(id object))defaultSerializer;
+ (id (^)(NSData *))defaultDeserializer;

+ (NSData *(^)(id object))timestampSerializer;
+ (id (^)(NSData *))timestampDeserializer;
 
- (id)initWithPath:(NSString *)path;

- (id)initWithPath:(NSString *)path
        serializer:(NSData *(^)(id object))serializer
      deserializer:(id (^)(NSData *))deserializer;

- (id)initWithPath:(NSString *)path objectSerializer:(NSData *(^)(id object))objectSerializer
                                  objectDeserializer:(id (^)(NSData *))objectDeserializer
                                  metadataSerializer:(NSData *(^)(id object))metadataSerializer
                                metadataDeserializer:(id (^)(NSData *))metadataDeserializer;

@property (nonatomic, strong, readonly) NSString *databasePath;

@property (nonatomic, strong, readonly) NSData *(^objectSerializer)(id object);
@property (nonatomic, strong, readonly) id (^objectDeserializer)(NSData *data);

@property (nonatomic, strong, readonly) NSData *(^metadataSerializer)(id object);
@property (nonatomic, strong, readonly) id (^metadataDeserializer)(NSData *data);

*/

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
