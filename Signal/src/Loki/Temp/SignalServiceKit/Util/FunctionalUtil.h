//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSArray (FunctionalUtil)

/// Returns true when any of the items in this array match the given predicate.
- (bool)any:(int (^)(id item))predicate;

/// Returns true when all of the items in this array match the given predicate.
- (bool)all:(int (^)(id item))predicate;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)map:(id (^)(id item))projection;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)filter:(int (^)(id item))predicate;

- (NSDictionary *)groupBy:(id (^)(id value))keySelector;

@end

NS_ASSUME_NONNULL_END
