#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseViewTypes.h"

#import "YapDatabaseAutoViewConnection.h"
#import "YapDatabaseAutoViewTransaction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 * 
 * https://github.com/yapstudios/YapDatabase
 * 
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseAutoView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
**/
@interface YapDatabaseAutoView : YapDatabaseView

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting;

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(nullable NSString *)versionTag;

/**
 * See the wiki for an example of how to initialize a view:
 * https://github.com/yapstudios/YapDatabase/wiki/Views#wiki-initializing_a_view
 *
 * @param grouping
 *   The grouping block handles both filtering and grouping.
 *   There are multiple groupingBlock types that are supported.
 *   
 *   @see YapDatabaseViewTypes.h for block type definitions.
 * 
 * @param sorting
 *   The sorting block handles sorting of objects within their group.
 *   There are multiple sortingBlock types that are supported.
 *   
 *   @see YapDatabaseViewTypes.h for block type definitions.
 *
 * @param versionTag
 *   If, after creating a view, you need to change either the groupingBlock or sortingBlock,
 *   then simply use the versionTag parameter. If you pass a versionTag that is different from the last
 *   initialization of the view, then the view will automatically flush its tables, and re-populate itself.
 *
 * @param options
 *   The options allow you to specify things like creating an in-memory-only view (non persistent).
**/
- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(nullable NSString *)versionTag
                         options:(nullable YapDatabaseViewOptions *)options;


@property (nonatomic, strong, readonly) YapDatabaseViewGrouping *grouping;
@property (nonatomic, strong, readonly) YapDatabaseViewSorting *sorting;

@end

NS_ASSUME_NONNULL_END
