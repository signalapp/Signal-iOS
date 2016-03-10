#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The YapSet class can be treated more or less like a regular NSSet.
 *
 * It is designed to expose internal mutable objects to the external world.
 * That is, we skip all the overhead associated with making immutable copies,
 * and instead just use this simple wrapper class.
 * 
 * In general, the external world won't interact with this class.
 * They are encouraged to instead use the changeset methods exposed in the connection classes.
 * 
 * @see YapDatabaseConnection hasChangeForKey:inNotifications:
 * @see YapDatabaseConnection hasChangeForAnyKeys:inNotifications:
**/
@interface YapSet : NSObject <NSFastEnumeration>

- (id)initWithSet:(NSMutableSet *)set;
- (id)initWithDictionary:(NSMutableDictionary *)dictionary;

// NSSet methods

@property (nonatomic, readonly) NSUInteger count;

- (BOOL)containsObject:(id)anObject;
- (BOOL)intersectsSet:(NSSet *)otherSet;

- (void)enumerateObjectsUsingBlock:(void (^)(id obj, BOOL *stop))block;

// It's open source!
// You are encouraged to add any methods you may need that are available in the NSSet API.
//
// Not every method from NSSet is available here because the author is lazy,
// and only implemented what was needed at the time.
//
// If you add something, keep in mind the spirit of this class.
// It is designed to expose mutable internals in a safe (immutable) manner.
// It is designed to expose them in the form of a set.
//
// If you make improvements, feel free to submit a patch to the github project and get some good karma for it!
// https://github.com/yapstudios/YapDatabase

@end

NS_ASSUME_NONNULL_END
