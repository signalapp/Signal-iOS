#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseCrossProcessNotificationConnection.h"
#import "YapDatabaseCrossProcessNotificationTransaction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * `YapDatabaseCrossProcessNotification` is an extension which allows you to be notified when the
 * database has been updated in another process.
 *
 * A `YapDatabaseModifiedExternallyNotification` notification is posted on the main thread.
 *
 * This is useful when the `enableMutiprocessSupport` option has been set, to be notified of external
 * changes and having an opportunity to reload a view.
 *
 * All processes using the database should declare the extension.
 *
 * An identifier permits to distinguish each database, and all processes listening on the same database
 * must use the same identifier.
 *
**/
@interface YapDatabaseCrossProcessNotification : YapDatabaseExtension

- (id)initWithIdentifier:(NSString *)identifier;

@property (nonatomic, readonly) NSString* identifier;

@end

NS_ASSUME_NONNULL_END
