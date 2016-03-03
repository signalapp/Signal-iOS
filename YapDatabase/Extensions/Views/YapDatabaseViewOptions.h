#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"

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

@interface YapDatabaseViewOptions : NSObject <NSCopying>

/**
 * A view can either be persistent (saved to sqlite), or non-persistent (kept in memory only).
 *
 * A persistent view saves its content to sqlite database tables.
 * Thus a persistent view can be restored on subsequent app launches with re-population.
 *
 * A non-persistent view is stored in memory.
 * From the outside, it works exactly like a persistent view in every way.
 * You won't be able to tell the difference unless you look at the sqlite database.
 *
 * It's recommended that you use a persistent view for any views that your app needs on a regular basis.
 * For example, if your app's main screen has a tableView powered by a view, that should likely be persistent.
 *
 * Non-persistent views are recommended for those situations where you need a view only temporarily.
 * Or where the configuration of the view is highly dependent upon parameters that change regularly.
 * In general, situations where it doesn't really make sense to persist the view.
 *
 * The default value is YES.
**/
@property (nonatomic, assign, readwrite) BOOL isPersistent;

/**
 * You can configure the view to pre-filter all but a subset of collections.
 * 
 * The primary motivation for this is to reduce the overhead when first populating the view.
 * For example, if you're creating a view which only includes objects from a single collection,
 * then you could specify that collection here. So when the view first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over all collections.
 * And enumerating a small subset of the entire database during view population can improve speed,
 * especially with larger databases.
 * 
 * In addition to reducing the overhead when first populating the view,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the groupingBlock will never be invoked, and the view will act as if the groupingBlock returned nil.
 * 
 * For all rows whose collection is in the allowedCollections, the view acts normally.
 * So the groupingBlock would still be invoked as normal.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;

/**
 * You can configure the view to skip the initial view population.
 *
 * The default value is NO.
**/
@property (nonatomic, assign, readwrite) BOOL skipInitialViewPopulation;

@end

NS_ASSUME_NONNULL_END
