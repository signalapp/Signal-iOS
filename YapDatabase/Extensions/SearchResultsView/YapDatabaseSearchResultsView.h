#import <Foundation/Foundation.h>

#import "YapDatabaseAutoView.h"
#import "YapDatabaseSearchResultsViewOptions.h"
#import "YapDatabaseSearchResultsViewConnection.h"
#import "YapDatabaseSearchResultsViewTransaction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseSearchResults allows you to pipe search results from YapDatabaseFullTextSearch into a YapDatabaseView.
 * This makes it easy to display search results in a tableView or collectionView.
**/
@interface YapDatabaseSearchResultsView : YapDatabaseAutoView

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
 * @param fullTextSearchName
 *   The registeredName of a YapDatabaseFullTextSearch extension.
 *   The fts extension must already be registered with the database system.
 * 
 * @param parentViewName
 *   The registeredName of a YapDatabaseView extension.
 *   The view extension must already be registered with the database system.
 * 
 * @param versionTag
 *   The standard versionTag mechanism.
 * 
 * @param options
 * 
 *   Extended options for the extension.
 *   You may pass nil to get the default extended options.
**/
- (id)initWithFullTextSearchName:(NSString *)fullTextSearchName
                  parentViewName:(NSString *)parentViewName
                      versionTag:(nullable NSString *)versionTag
                         options:(nullable YapDatabaseSearchResultsViewOptions *)options;

/**
 * In this configuration, you want to pipe search results directly into a new YapDatabaseView.
 * That is, there is not an existing YapDatabaseView you want to search.
 * Rather, you simply want to perform a search using a YapDatabaseFullTextSearch extension,
 * and then provide a groupingBlock / sortingBlock in order to present the results.
 * 
 * @param fullTextSearchName
 *   The registeredName of a YapDatabaseFullTextSearch extension.
 *   The fts extension must already be registered with the database system.
 * 
 * @param grouping
 *   The groupingBlock is used to place search results into proper sections.
 *   The block may also be used to perform secondary filtering.
 * 
 * @param sorting
 *   The sortingBlock is used to sort search results within their respective sections.
 * 
 * @param versionTag
 *   The standard versionTag mechanism.
 * 
 * @param options
 *   Extended options for the extension.
 *   You may pass nil to get the default extended options.
 * 
 * For more information on the groupingBlock & sortingBlock parmaters,
 * please see the documentation in YapDatabaseView.h.
**/
- (id)initWithFullTextSearchName:(NSString *)fullTextSearchName
                        grouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(nullable NSString *)versionTag
                         options:(nullable YapDatabaseSearchResultsViewOptions *)options;


@property (nonatomic, strong, readonly) NSString *fullTextSearchName;

@property (nonatomic, strong, readonly) NSString *parentViewName;

@end

NS_ASSUME_NONNULL_END
