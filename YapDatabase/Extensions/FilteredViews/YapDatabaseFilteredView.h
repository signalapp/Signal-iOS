#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"

#import "YapDatabaseFilteredViewTypes.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseFilteredView : YapDatabaseView

/**
 * @param parentViewName
 *
 *   The parentViewName must be the registered name of a YapDatabaseView or
 *   YapDatabaseFilteredView extension.
 *   That is, you must first register the parentView, and then use that registered name here.
 *
 * @param filtering
 *
 *   The filteringBlock allows you to filter items from this view that exist in the parent view.
 *   There are multiple filteringBlock types that are supported.
 *
 *   @see YapDatabaseViewTypes.h for block type definitions.
 *
 * @param versionTag
 *
 *   The filteringBlock may be changed after the filteredView is created (see YapDatabaseFilteredViewTransaction).
 *   This is often in association with user events.
 *   The versionTag helps to identify the filteringBlock being used.
 *   During initialization of the view, the view will compare the passed tag to what it has stored from a previous
 *   app session. If the tag matches, then the filteredView is already setup. Otherwise the view will automatically
 *   flush its tables, and re-populate itself.
 *
 * @param options
 *
 *   The options allow you to specify things like creating an IN-MEMORY-ONLY VIEW (non persistent).
**/

- (id)initWithParentViewName:(NSString *)viewName
                   filtering:(YapDatabaseViewFiltering *)filtering;

- (id)initWithParentViewName:(NSString *)viewName
                   filtering:(YapDatabaseViewFiltering *)filtering
                  versionTag:(nullable NSString *)versionTag;

- (id)initWithParentViewName:(NSString *)viewName
                   filtering:(YapDatabaseViewFiltering *)filtering
                  versionTag:(nullable NSString *)versionTag
                     options:(nullable YapDatabaseViewOptions *)options;


@property (nonatomic, strong, readonly) NSString *parentViewName;

@property (nonatomic, strong, readonly) YapDatabaseViewFiltering *filtering;

@end

NS_ASSUME_NONNULL_END
