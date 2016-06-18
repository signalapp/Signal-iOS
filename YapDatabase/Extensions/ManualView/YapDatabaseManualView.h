#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"

#import "YapDatabaseManualViewConnection.h"
#import "YapDatabaseManualViewTransaction.h"

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
@interface YapDatabaseManualView : YapDatabaseView

- (instancetype)init;

- (instancetype)initWithVersionTag:(nullable NSString *)versionTag
                           options:(nullable YapDatabaseViewOptions *)options;

@end

NS_ASSUME_NONNULL_END
