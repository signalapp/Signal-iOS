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

/**
 * These are all dummy values.
 * We're not trying to do anything special here.
 * Just trying to make the object big enough to represent something that may be used in a real application.
**/

@property (nonatomic, strong, readonly) NSString * string1;
@property (nonatomic, strong, readonly) NSString * string2;
@property (nonatomic, strong, readonly) NSString * string3;
@property (nonatomic, strong, readonly) NSString * string4;
@property (nonatomic, strong, readonly) NSNumber * number;
@property (nonatomic, strong, readonly) NSArray  * array;
@property (nonatomic, assign, readonly) double     pDouble; // primitives work too

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
 * If you go this route, checkout the YapDatabase+Timestamp category, which has a bunch of useful helper methods.
 * 
 * Another common usage is to use a subset of the full object as metadata.
 * This is because metadata is kept in RAM for fast access without ever hitting the disk.
 * So if you have a large object, but often need access to certain fields (perhaps for summary display or sorting),
 * you can choose to keep just those fields in RAM for instant access,
 * and allow the rest of the object graph to be paged out to disk.
 * 
 * As you can see, metadata can be very flexible.
 * This example uses a small metadata subset object.
**/
@interface TestObjectMetadata : NSObject <NSCoding>

@property (nonatomic, strong, readonly) NSString * string1;
@property (nonatomic, assign, readonly) double     pDouble;

@end
