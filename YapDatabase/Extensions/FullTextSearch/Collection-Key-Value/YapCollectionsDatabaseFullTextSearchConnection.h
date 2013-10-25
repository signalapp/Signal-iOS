#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"

@class YapCollectionsDatabaseFullTextSearch;

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapCollectionsDatabaseFullTextSearch is an extension for performing text based search.
 * Internally it uses sqlite's FTS module which was contributed by Google.
 * 
 * As an extension, YapCollectiosnDatabaseFullTextSearchConnection is automatically
 * created by YapCollectionsDatabaseConnnection. You can access this object via:
 *
 * [databaseConnection extension:@"myRegisteredExtensionName"]
 *
 * @see YapCollectionsDatabaseFullTextSearch
 * @see YapCollectionsDatabaseFullTextSearchTransaction
**/
@interface YapCollectionsDatabaseFullTextSearchConnection : YapAbstractDatabaseExtensionConnection

/**
 * Returns the parent instance.
**/
@property (nonatomic, strong, readonly) YapCollectionsDatabaseFullTextSearch *fullTextSearch;

@end
