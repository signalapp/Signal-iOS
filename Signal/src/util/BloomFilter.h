#import <Foundation/Foundation.h>

/**
 *
 * A bloom filter allows a set of items to be represented compactly, at the cost of false-positives when checking membership.
 * When contains returns true, the given item may be in the set.
 * When contains returns false, the given item is definitely not in the set.
 *
 * Bloom filters are used to opportunistically avoid starting an expensive operation that always fails for items not in a set.
 * In the specific case of RedPhone, it is used to determine if a phone number can be called (i.e. is in the RedPhone directory).
 *
 */
@interface BloomFilter : NSObject

@property (nonatomic, readonly) NSUInteger hashCount;
@property (nonatomic, readonly) NSData* data;

- (instancetype)initWithHashCount:(NSUInteger)hashCount
                          andData:(NSData*)data;
- (instancetype)initWithNothing;
- (instancetype)initWithEverything;

- (bool)contains:(NSString*)entity;

@end
