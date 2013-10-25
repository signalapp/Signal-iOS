#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"

@class YapDatabaseFullTextSearch;

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseFullTextSearch is an extension for performing text based search.
 * Internally, it uses sqlite's FTS module which was contributed by Google.
 * 
 * As an extension, YapDatabaseFullTextSearchConnection is automatically created by YapDatabaseConnnection.
 * You can access this object via:
 *
 * [databaseConnection extension:@"myRegisteredExtensionName"]
 *
 * @see YapDatabaseFullTextSearch
 * @see YapDatabaseFullTextSearchTransaction
**/
@interface YapDatabaseFullTextSearchConnection : YapAbstractDatabaseExtensionConnection

/**
 * Returns the parent instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseFullTextSearch *fullTextSearch;

@end
