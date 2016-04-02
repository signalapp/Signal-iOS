#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseViewTypes.h"
#import "YapDatabaseViewOptions.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewMappings.h"
#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewRangeOptions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 * 
 * https://github.com/yapstudios/YapDatabase
 * 
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
**/
@interface YapDatabaseView : YapDatabaseExtension

/**
 * See the wiki for an example of how to initialize a view:
 * https://github.com/yapstudios/YapDatabase/wiki/Views#wiki-initializing_a_view
 *
 * @param grouping
 * 
 *   The grouping block handles both filtering and grouping.
 *   There are multiple groupingBlock types that are supported.
 *   
 *   @see YapDatabaseViewTypes.h for block type definitions.
 * 
 * @param sorting
 * 
 *   The sorting block handles sorting of objects within their group.
 *   There are multiple sortingBlock types that are supported.
 *   
 *   @see YapDatabaseViewTypes.h for block type definitions.
 *
 * @param versionTag
 *
 *   If, after creating a view, you need to change either the groupingBlock or sortingBlock,
 *   then simply use the versionTag parameter. If you pass a versionTag that is different from the last
 *   initialization of the view, then the view will automatically flush its tables, and re-populate itself.
 *
 * @param options
 *
 *   The options allow you to specify things like creating an in-memory-only view (non persistent).
**/

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting;

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(nullable NSString *)versionTag;

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(nullable NSString *)versionTag
                         options:(nullable YapDatabaseViewOptions *)options;


@property (nonatomic, strong, readonly) YapDatabaseViewGrouping *grouping;
@property (nonatomic, strong, readonly) YapDatabaseViewSorting *sorting;

/**
 * The versionTag assists you in updating your blocks.
 *
 * If you need to change the groupingBlock or sortingBlock,
 * then simply pass a different versionTag during the init method, and the view will automatically update itself.
 * 
 * If you want to keep things simple, you can use something like @"1",
 * representing version 1 of my groupingBlock & sortingBlock.
 * 
 * For more advanced applications, you may also include within the versionTag string:
 * - localization information (if you're using localized sorting routines)
 * - configuration information (if your sorting routine is based on some in-app configuration)
 *
 * For example, if you're sorting strings using a localized string compare method, then embedding the localization
 * information into your versionTag means the view will automatically re-populate itself (re-sort)
 * if the user launches the app in a different language than last time.
 * 
 * NSString *localeIdentifier = [[NSLocale currentLocale] localeIdentifier];
 * NSString *versionTag = [NSString stringWithFormat:@"1-%@", localeIdentifier];
 * 
 * The groupingBlock/sortingBlock/versionTag can me changed after the view has been created.
 * See YapDatabaseViewTransaction(ReadWrite).
 * 
 * Note:
 * - [YapDatabaseView versionTag]            = versionTag of most recent commit
 * - [YapDatabaseViewTransaction versionTag] = versionTag of this commit
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

/**
 * The options allow you to specify things like creating an in-memory-only view (non persistent).
**/
@property (nonatomic, copy, readonly) YapDatabaseViewOptions *options;

/**
 * Allows you to fetch the versionTag from a view that was registered during the last app launch.
 * 
 * For example, let's say you have a view that sorts contacts.
 * And you support 2 different sort options:
 * - First, Last
 * - Last, First
 * 
 * To support this, you use 2 different versionTags:
 * - "First,Last"
 * - "Last,First"
 * 
 * And you want to ensure that when you first register the view (during app launch),
 * you choose the same block & versionTag from a previous app launch (if possible).
 * This prevents the view from enumerating the database & re-populating itself
 * during registration if the versionTag is different from last time.
 * 
 * So you can use this method to fetch the previous versionTag.
**/
+ (NSString *)previousVersionTagForRegisteredViewName:(NSString *)name
                                      withTransaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
