#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseHooks;


@interface YapDatabaseHooksConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent extension instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseHooks *parent;

@end
