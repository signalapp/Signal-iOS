#import <Foundation/Foundation.h>

/**
 * This is an example base class that demonstrates certain concepts you'll likely find useful when using YapDatabase.
 * 
 * **** You do NOT have to use this base class. ****
 *
 * If you thought, for a moment, that YapDatabase enforces a base class like NSManagedObject (gag)
 * please banish that thought from your mind now.
 * 
 * Truth be told, YapDatabase doesn't care what your objects look like.
 * Just so long as you're able to properly serialize & deserialize them.
 * Which means that you're more than welcome to use plain old NSObject subclasses.
 * Or maybe even an open source project like one of these:
 * 
 * - https://github.com/Mantle/Mantle
 * - https://github.com/nicklockwood/FastCoding
 * 
 * It's completely up to you!
 * 
 * That being said, I think you'll find some of the concepts demonstrated here to be useful.
 * So feel free to copy & modify anything in this class. Meld it to fit your needs.
 * Maybe you'll even merge some of the concepts in this class with other popular open source projects
 * to create your own super base class. :)
 * 
 * ***** Concept #1 *****
 * 
 * With a highly concurrent database (like YapDatabase), thread-safety becomes important.
 * But you don't want thread-safety to become burdensome. What you really want is something so simple and
 * straight-forward that you don't have to think about it (yet it's automatically thread-safe).
 * 
 * I touch on several thread-safety issues in the "Thread Safety" wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Thread-Safety
 * 
 * But you can make life really easy on yourself if you use immutable objects.
 * Of course, you must be thinking, "easier said than done" right?
 * Or perhaps "that sounds like a pain in the ass"?
 *
 * Surprisingly, it only takes a few lines of code!
 * I explain the concept in depth here (along with a bonus performance improvement you can get from it):
 * https://github.com/yapstudios/YapDatabase/wiki/Object-Policy
 * 
 * But here's a 10,000 foot summary:
 * - Your model objects extend this one (or you rip off this class - feel free)
 * - You simply call [object makeImmutable]
 * - Voilà, you've got yourself an immutable thread-safe object,
 *   ready to go in the database and be passed around from thread-to-thread like a ... well behaved object.
 *
 * ***** Concept #2 *****
 * 
 * Tracking which properties of an object have been changed.
 *
 * This has a variety of useful applications.
 * You can use it distinguish UI fields which have been changed.
 * Or to mark a window as dirty when the corresponding object has unsaved changes.
 *
 * It can also simplify code by allowing you to directly pass an object to another method for mutation.
 * And the caller can simply check the object afterwards to see if it needs to be saved.
 * 
 * ***** Concept #3 *****
 * 
 * Syncing the object with a cloud-based service.
 * 
 * There are often differences between the object that you store locally, and the object that's stored in the cloud.
 * For example:
 * 
 * - Locally you store a UIColor object, but in the cloud you store a string (r,g,b,a)
 * - Locally your variable is named 'isComplete', but in the cloud it's unfortunately misspelled as 'isCompete'.
 *
 * These changes accumulate over time.
 * And this class provides several easy techniques to provide easy mapping between local & remote (keys/values).
 *
 * This technique is recommended for the YapDatabaseCloudKit extension:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit
**/


@interface MyDatabaseObject : NSObject <NSCopying>


#pragma mark Class configuration

+ (NSMutableSet *)monitoredProperties;
@property (nonatomic, readonly) NSSet *monitoredProperties;

+ (NSMutableDictionary *)mappings_localKeyToCloudKey;
@property (nonatomic, readonly) NSDictionary *mappings_localKeyToCloudKey;

+ (NSMutableDictionary *)mappings_cloudKeyToLocalKey;
@property (nonatomic, readonly) NSDictionary *mappings_cloudKeyToLocalKey;

+ (BOOL)storesOriginalCloudValues;


#pragma mark Immutability

@property (nonatomic, readonly) BOOL isImmutable;

- (void)makeImmutable;

- (NSException *)immutableExceptionForKey:(NSString *)key;


#pragma mark Monitoring (local)

@property (nonatomic, readonly) NSSet *changedProperties;
@property (nonatomic, readonly) BOOL hasChangedProperties;

- (void)clearChangedProperties;


#pragma mark Monitoring (cloud)

@property (nonatomic, readonly) NSSet *allCloudProperties;

@property (nonatomic, readonly) NSSet *changedCloudProperties;
@property (nonatomic, readonly) BOOL hasChangedCloudProperties;

@property (nonatomic, readonly) NSDictionary *originalCloudValues;


#pragma mark Getters & Setters (cloud)

- (NSString *)cloudKeyForLocalKey:(NSString *)localKey;
- (NSString *)localKeyForCloudKey:(NSString *)cloudKey;

- (id)cloudValueForCloudKey:(NSString *)key;
- (id)cloudValueForLocalKey:(NSString *)key;

- (id)localValueForCloudKey:(NSString *)key;
- (id)localValueForLocalKey:(NSString *)key;

- (void)setLocalValueFromCloudValue:(id)cloudValue forCloudKey:(NSString *)cloudKey;

/**
 * You can use this macro WITHIN SUBCLASSES to fetch the CloudKey for a given property.
 * For example, say your class is configured with the following mappings_localKeyToCloudKey:
 * @{ @"uuid" : @"uuid"
 *    @"foo"  : @"bar"
 * }
 *
 * Then:
 * - CloudKey(uuid) => [self.mappings_localKeyToCloudKey objectForKey:@"uuid"] => @"uuid"
 * - CloudKey(foo)  => [self.mappings_localKeyToCloudKey objectForKey:@"foo"]  => @"bar"
 *
 * If using Apple's CloudKit framework,
 * then this macro returns the name of the corresponding property within the CKRecord.
**/
#define CloudKey(ivar) [self.mappings_localKeyToCloudKey objectForKey:@"" # ivar]
//    translation  ==> [self.mappings_localKeyToCloudKey objectForKey:@"ivar"]

@end
