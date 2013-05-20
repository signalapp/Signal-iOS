#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseView.h"

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
 * Thus any objects that support the NSCoding protocol may be used.
 *
 * Many of Apple's primary data types support NSCoding out of the box.
 * It's easy to add NSCoding support to your own custom objects.
**/
+ (NSData *(^)(id object))defaultSerializer;
+ (id (^)(NSData *))defaultDeserializer;

/**
 * Property lists ONLY support the following: NSData, NSString, NSArray, NSDictionary, NSDate, and NSNumber.
 * Property lists are highly optimized and are used extensively Apple.
 * 
 * Property lists make a good fit when your existing code already uses them,
 * such as replacing NSUserDefaults with a database.
**/
+ (NSData *(^)(id object))propertyListSerializer;
+ (id (^)(NSData *))propertyListDeserializer;

/**
 * A FASTER serializer & deserializer than the default, if serializing ONLY a NSDate object.
 * You may want to use timestampSerializer & timestampDeserializer if your metadata is simply an NSDate.
**/
+ (NSData *(^)(id object))timestampSerializer;
+ (id (^)(NSData *))timestampDeserializer;

#pragma mark Init

/**
 * Opens or creates a sqlite database with the given path.
 * The default serializer and deserializer are used.
 * 
 * @see defaultSerializer
 * @see defaultDeserializer
**/
- (id)initWithPath:(NSString *)path;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializer and deserializer are used for both objects and metadata.
**/
- (id)initWithPath:(NSString *)path
        serializer:(NSData *(^)(id object))serializer
      deserializer:(id (^)(NSData *))deserializer;

/**
 * Opens or creates a sqlite database with the given path.
 * The given serializers and deserializers are used.
**/
- (id)initWithPath:(NSString *)path objectSerializer:(NSData *(^)(id object))objectSerializer
                                  objectDeserializer:(id (^)(NSData *))objectDeserializer
                                  metadataSerializer:(NSData *(^)(id object))metadataSerializer
                                metadataDeserializer:(id (^)(NSData *))metadataDeserializer;

#pragma mark Properties

@property (nonatomic, strong, readonly) NSString *databasePath;

@property (nonatomic, strong, readonly) NSData *(^objectSerializer)(id object);
@property (nonatomic, strong, readonly) id (^objectDeserializer)(NSData *data);

@property (nonatomic, strong, readonly) NSData *(^metadataSerializer)(id object);
@property (nonatomic, strong, readonly) id (^metadataDeserializer)(NSData *data);


#pragma mark Views

/**
 * Registers the view with the database using the given name.
 * After registration everything works automatically using just the view name.
 * 
 * @return
 *     YES if the view was properly registered.
 *     NO if an error occurred, such as the viewName is already registered.
**/
- (BOOL)registerView:(YapAbstractDatabaseView *)view withName:(NSString *)viewName;

/**
 * Returns the registered view with the given name.
**/
- (YapAbstractDatabaseView *)registeredView:(NSString *)viewName;

/**
 * Returns all currently registered views as a dictionary.
 * The key is the registed name (NSString), and the value is the view (YapAbstractDatabaseView subclass).
**/
- (NSDictionary *)registeredViews;

@end
