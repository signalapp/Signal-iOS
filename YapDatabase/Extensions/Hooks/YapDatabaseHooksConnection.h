#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseHooks;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseHooksConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent extension instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseHooks *parent;

@end

NS_ASSUME_NONNULL_END
