//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface NSArray <ObjectType>(FunctionalUtil)

/// Returns the first item in the array satisfying the predicate
- (nullable ObjectType)firstSatisfying:(BOOL (^)(ObjectType item))predicate;

/// Returns true when any of the items in this array match the given predicate.
- (BOOL)anySatisfy:(BOOL (^)(ObjectType item))predicate;

/// Returns true when all of the items in this array match the given predicate.
- (BOOL)allSatisfy:(BOOL (^)(ObjectType item))predicate;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)map:(id (^)(ObjectType item))projection;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray<ObjectType> *)filter:(BOOL (^)(ObjectType item))predicate;

- (NSDictionary<id, NSArray<ObjectType> *> *)groupBy:(id (^)(id value))keySelector;

@end

NS_ASSUME_NONNULL_END
