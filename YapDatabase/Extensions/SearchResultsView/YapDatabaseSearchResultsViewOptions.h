#import <Foundation/Foundation.h>

#import "YapDatabaseViewOptions.h"
#import "YapWhitelistBlacklist.h"
#import "YapDatabaseFullTextSearchSnippetOptions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Note: This class extends YapDatabaseViewOptions.
**/
@interface YapDatabaseSearchResultsViewOptions : YapDatabaseViewOptions <NSCopying>

/**
 * Inherited by YapDatabaseViewOptions.
 * See YapDatabaseViewOptions.h for documentation.
 *
 * The default value is ** NO **. <<-- This is changed for YapDatabaseSearchResultsOptions
**/
//@property (nonatomic, assign, readwrite) BOOL isPersistent;


/**
 * Allows you to filter which groups in the parentView are used to create the union'd search results.
 * 
 * This is especially powerful if the parentView is rather large, but you're only displaying a few groups from it.
 * That way the YapDatabaseSearchResults ignores all but the given groups when performing the merge.
 * 
 * Note: This property only applies if using a parentView.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedGroups;

/**
 * Set this option to include snippets with the search results.
 *
 * The default value is nil.
**/
@property (nonatomic, copy, readwrite, nullable) YapDatabaseFullTextSearchSnippetOptions *snippetOptions;

@end

NS_ASSUME_NONNULL_END
