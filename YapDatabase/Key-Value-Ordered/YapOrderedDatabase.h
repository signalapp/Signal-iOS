#import "YapDatabase.h"

#import "YapOrderedDatabaseConnection.h"
#import "YapOrderedDatabaseTransaction.h"


/**
 * This class extendes YapDatabase.
 * It provides ordering for objects that otherwise have no explicit ordering.
 * 
 * YapDatabase is a key-value storage facility.
 * You can store objects along with optional metadata for each object.
 * Sometimes objects stored to the database have an explicit ordering.
 * For example, objects may be sorted by name or timestamp.
 * However, this is not always the case.
 * Sometimes the order is determined by the user, or perhaps the order
 * comes from the server, and the client is simply downloading the objects in pages.
 * In these cases it may be helpful to allow the database layer to handle the logic
 * of maintaining the ordering of the objects, while you focus on the rest.
 * 
 * This class maintains an internal "array" which stores the order of the keys.
 * It automatically paginates the array, and stores the pages to the database.
 * This allows it to scale and support very large databases,
 * as adding an object to the database only requires updating a single small page of keys.
 * Additionally it can fault/unfault ordering pages in order to keep memory requirements low.
**/
@interface YapOrderedDatabase : YapDatabase

/* Inherited from YapDatabase

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
- (YapOrderedDatabaseConnection *)newConnection;

@end
