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
 * YapDatabaseCrossProcessNotification is an extension which allows you to be notified when database is updated in another process.
 *
**/
@interface YapDatabaseCrossProcessNotification : YapDatabaseExtension

- (id)initWithIdentifier:(NSString *)identifier;

@property (nonatomic, readonly) NSString* identifier;

@end

NS_ASSUME_NONNULL_END
