#import <Foundation/Foundation.h>


/**
 * This base class is shared by YapDatabase and YapCollectionsDatabase.
 * 
 * It provides the generic implementation of a database such as:
 * - common properties
 * - common initializers
 * - common setup code
 * - stub methods which are overriden by subclasses
**/
@interface YapAbstractDatabase : NSObject

#pragma mark Shared class methods

/**
 * The default serializer & deserializer use NSCoding (NSKeyedArchiver & NSKeyedUnarchiver).
 * Thus the objects need only support the NSCoding protocol.
**/
+ (NSData *(^)(id object))defaultSerializer;
+ (id (^)(NSData *))defaultDeserializer;

/**
 * A FASTER serializer & deserializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (NSData *(^)(id object))timestampSerializer;
+ (id (^)(NSData *))timestampDeserializer;

#pragma mark Shared instance methods

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

@end
