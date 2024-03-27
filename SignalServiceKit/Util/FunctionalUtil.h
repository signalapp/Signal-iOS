//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface NSArray <ObjectType>(FunctionalUtil)

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray *)map:(id (^)(ObjectType item))projection;

/// Returns an array of all the results of passing items from this array through the given projection function.
- (NSArray<ObjectType> *)filter:(BOOL (^)(ObjectType item))predicate;

@end

NS_ASSUME_NONNULL_END
