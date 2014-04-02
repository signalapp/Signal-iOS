#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseSearchResultsOptions.h"
#import "YapDatabaseSearchResultsConnection.h"
#import "YapDatabaseSearchResultsTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseSearchResults allows you to pipe search results from YapDatabaseFullTextSearch into a YapDatabaseView.
 * This makes it easy to display search results in a tableView or collectionView.
**/
@interface YapDatabaseSearchResults : YapDatabaseView

/**
 * In this configuration, you want to search an existing YapDatabaseView,
 * and you have a YapDatabaseFullTextSearch extension with which to do it.
 * 
 * The search results will be a union of those items that match the search,
 * and those items in the existing YapDatabaseView.
 * 
 * The search results will be grouped and sorted in the same manner as the parent YapDatabaseView.
 * This is conceptually similar to a YapDatabaseFilteredView,
 * where the filterBlock is automatically created according to the search parameter(s).
 * 
 * @param ftsName
 * 
 *   The registeredName of a YapDatabaseFullTextSearch extension.
 *   The fts extension must already be registered with the database system.
 * 
 * @param viewName
 * 
 *   The registeredName of a YapDatabaseView extension.
 *   The view extension must already be registered with the database system.
 * 
 * @param versionTag
 * 
 *   The standard versionTag mechanism.
 * 
 * @param options
 * 
 *   Extended options for the extension.
 *   You may pass nil to get the default extended options.
**/
- (id)initWithFullTextSearchName:(NSString *)fullTextSearchName
                  parentViewName:(NSString *)parentViewName
                  versionTag:(NSString *)versionTag
                     options:(YapDatabaseSearchResultsOptions *)options;

/**
 * 
**/
- (id)initWithFullTextSearchName:(NSString *)fullTextSearchName
                   groupingBlock:(YapDatabaseViewGroupingBlock)groupingBlock
               groupingBlockType:(YapDatabaseViewBlockType)groupingBlockType
                    sortingBlock:(YapDatabaseViewSortingBlock)sortingBlock
                sortingBlockType:(YapDatabaseViewBlockType)sortingBlockType
                      versionTag:(NSString *)versionTag
                         options:(YapDatabaseSearchResultsOptions *)options;


@property (nonatomic, strong, readonly) NSString *fullTextSearchName;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@end
