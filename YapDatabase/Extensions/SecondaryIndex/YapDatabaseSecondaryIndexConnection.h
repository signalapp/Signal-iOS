#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseSecondaryIndex;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseSecondaryIndexConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseSecondaryIndex *secondaryIndex;

/**
 * The queryCache speeds up the transaction methods. (enumerateXMatchingQuery:usingBlock:)
 *
 * In order for a query to be executed, it first has to be compiled by SQLite into an executable routine.
 * The queryCache stores these compiled reusable routines, so that repeated queries can be executed faster.
 *
 * Please note that, in terms of caching, only the queryString matters. The queryParameters do not.
 * That is, if you use the same queryString over and over, but with different parameters,
 * you will get a nice benefit from caching as it will be able to recyle the compiled routine,
 * and simply bind the different parameters each time.
 *
 * By default the queryCache is enabled and has a limit of 10.
 *
 * To disable the cache entirely, set queryCacheEnabled to NO.
 * To use an inifinite cache size, set the queryCacheLimit to ZERO.
**/
@property (atomic, assign, readwrite) BOOL queryCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger queryCacheLimit;

@end

NS_ASSUME_NONNULL_END
