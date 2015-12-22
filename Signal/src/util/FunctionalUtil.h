#import <Foundation/Foundation.h>

@interface NSArray (FunctionalUtil)

/// Returns true when any of the items in this array match the given predicate.
- (bool)any:(int (^)(id item))predicate;

/// Returns true when all of the items in this array match the given predicate.
- (bool)all:(int (^)(id item))predicate;

/// Returns the first item in this array that matches the given predicate, or else returns nil if none match it.
- (id)firstMatchingElseNil:(int (^)(id item))predicate;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)map:(id (^)(id item))projection;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)filter:(int (^)(id item))predicate;

/// Returns the sum of the doubles in this array of doubles.
- (double)sumDouble;

/// Returns the sum of the unsigned integers in this array of unsigned integers.
- (NSUInteger)sumNSUInteger;

/// Returns the sum of the integers in this array of integers.
- (NSInteger)sumNSInteger;

- (NSDictionary *)keyedBy:(id (^)(id))keySelector;
- (NSDictionary *)groupBy:(id (^)(id value))keySelector;

@end
