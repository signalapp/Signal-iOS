#import <Foundation/Foundation.h>

#import "YapActionable.h"
#import "YapActionItem.h"
#import "YapDatabaseActionManagerConnection.h"
#import "YapDatabaseActionManagerTransaction.h"
#import "YapDatabaseView.h"

@class Reachability;

NS_ASSUME_NONNULL_BEGIN

/**
 * This extension automatically monitors the database for objects that support the YapActionable protocol.
 *
 * Objects that support the YapActionable protocol relay information about "actions" that need to be taken.
 * This information includes things such as:
 * 
 * - when the action needs to be taken
 * - if it should be retried, and if so what delay to use
 * - whether or not the action requires an Internet connection
 * - the block to invoke in order to trigger the action
 *
 * This extension handles all aspects related to scheduling & executing YapActionItems.
 *
 * Examples of YapActionItems include things such as:
 *
 * - deleting items when they expire
 *   e.g.: removing cached files
 * - refreshing items when they've become "stale"
 *   e.g.: periodically updating user infromation from the server
**/
@interface YapDatabaseActionManager : YapDatabaseView

- (instancetype)init;
- (instancetype)initWithOptions:(nullable YapDatabaseViewOptions *)options;

/**
 * YapDatabaseActionManager relies on a reachability instance to monitory for internet connectivity.
 * This is to support the YapActionItem.requiresInternet property.
 * 
 * If an instance is not assigned, then one will be automatically created (after registration)
 * via [Reachability reachabilityForInternetConnection].
**/
@property (atomic, strong, readwrite, nullable) Reachability *reachability;

@end

NS_ASSUME_NONNULL_END
