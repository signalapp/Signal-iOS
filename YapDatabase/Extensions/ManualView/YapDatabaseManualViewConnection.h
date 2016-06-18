#import <Foundation/Foundation.h>

#import "YapDatabaseViewConnection.h"

@class YapDatabaseView;
@class YapDatabaseManualView;

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseManualView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
 *
 *
 * As an extension, YapDatabaseManualViewConnection is automatically created by YapDatabaseConnnection.
 * You can access this object via:
 *
 * [databaseConnection extension:@"myRegisteredViewName"]
 *
 * @see YapDatabaseManualView
 * @see YapDatabaseManualViewTransaction
**/
@interface YapDatabaseManualViewConnection : YapDatabaseViewConnection

// Returns properly typed parent view instance
@property (nonatomic, strong, readonly) YapDatabaseManualView *manualView;

@end

NS_ASSUME_NONNULL_END
