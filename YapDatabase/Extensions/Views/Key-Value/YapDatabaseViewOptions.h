#import <Foundation/Foundation.h>


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


// This class is a placeholder for future additional options.

@end
