#import <Foundation/Foundation.h>

@class TestObjectMetadata;

/**
 * You can place any kind of object into the database so long as it can be archived / unarchived.
 * That is, the database needs to be able to turn the object into NSData (archive),
 * and then recreate the object later from that data (unarchive).
 * 
 * YapDatabase actually supports configurable serializers / deserializers.
 * So you can fully configure how your app goes about doing the archiving / unarchiving.
 * 
 * But the most simple (and Apple supported) technique for this is the NSCoding protocol.
 * If you're not already familiar with it, you have nothing to fear! It's extremely simple!
 * Follow these 3 steps:
 * 1. Add the <NSCoding> protocol specifier to the header file of your class
 * 2. Implement encodeWithCoder: method (archiving)
 * 3. Implement initWithCoder: method (unarchiving)
 * 
 * Take a look at the implementation of this class to see how simple it is.
**/
@interface TestObject : NSObject <NSCoding>

+ (TestObject *)generateTestObject;
+ (TestObject *)generateTestObjectWithSomeDate:(NSDate *)someDate someInt:(int)someInt;

/**
 * These are all dummy values.
 * We're not trying to do anything special here.
 * Just trying to make the object somewhat represent something that may be used in a real application.
**/

@property (nonatomic, strong, readonly) NSString * someString;
@property (nonatomic, strong, readonly) NSNumber * someNumber;
@property (nonatomic, strong, readonly) NSDate   * someDate;
@property (nonatomic, strong, readonly) NSArray  * someArray;
@property (nonatomic, assign, readonly) int        someInt;
@property (nonatomic, assign, readonly) double     someDouble;

- (TestObjectMetadata *)extractMetadata;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Metadata is entirely optional.
 * If you want to use metadata, you can use whatever you want.
 *
 * One common usage for metadata is timestamps.
 * For example, if you're downloading data from a server somewhere,
 * you might use metadata to timestamp when you originally fetched it.
 * You can later refer to the timestamp to decide if the data is stale and needs to be refreshed.
 * 
 * Another common usage is to use a small subset of a large object as metadata.
 * This can reduce overhead if the metadata fields are needed often, but the full object is rarely needed.
 * 
 * Thus metadata can be very flexible.
 * 
 * This example is rather silly because the object itself isn't big.
 * This example is just here to demonstrate that you can use a custom metadata object too.
**/
@interface TestObjectMetadata : NSObject <NSCoding>

@property (nonatomic, strong, readonly) NSDate * someDate;
@property (nonatomic, assign, readonly) int      someInt;

@end
