#import <Foundation/Foundation.h>

#import "YapActionable.h"
#import "YapActionItem.h"
#import "YapDatabaseActionManagerConnection.h"
#import "YapDatabaseActionManagerTransaction.h"
#import "YapDatabaseAutoView.h"
#import "YapReachability.h"

@class YapDatabaseConnection;

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
@interface YapDatabaseActionManager : YapDatabaseAutoView

- (instancetype)init;
- (instancetype)initWithConnection:(nullable YapDatabaseConnection *)connection;
- (instancetype)initWithConnection:(nullable YapDatabaseConnection *)connection
                           options:(nullable YapDatabaseViewOptions *)options;

#if !TARGET_OS_WATCH
/**
 * YapDatabaseActionManager relies on a reachability instance to monitory for internet connectivity.
 * This is to support the YapActionItem.requiresInternet property.
 * 
 * If an instance is not assigned, then one will be automatically created (after registration)
 * via [YapReachability reachabilityForInternetConnection].
**/
@property (atomic, strong, readwrite, nullable) YapReachability *reachability;
#endif

#pragma mark Suspend & Resume

/**
 * The YapDatabaseActionManager instance can be suspended/resumed via its suspendCount.
 *
 * You MUST match every call to suspend with a matching call to resume.
 * For example, if you invoke suspend 3 times, then the extension won't resume until you've invoked resume 3 times.
 *
 * This may be used to delay starting the ActionManager during app launch.
 * That is, typically the ActionManager begins operating as soon as the extension has been registered with the database.
 * But you may have YapActionItems that require other app components to be available.
 * If this is the case, you can keep the action manager in a suspended state until the app is ready.
 *
 * It may also be used when shutting down a YapDatabase instance.
 * To do so typically requires shutting down all associated YapDatabaseConnection instances.
 * If you instantiate the YDBActionManager instance with an explicit connection,
 * then it will only hold a weak reference to the connection. However, if you don't provide an explicit connection,
 * then YDBActionManager will create its own internal connection (with a strong reference). This would create
 * a retain cycle if you were attemping to shut down the YapDatabase instance. However, you can break the
 * retain cycle by suspending the action manager. When suspended, YDBActionManager automatically releases its
 * strongly held internal YDBConnection.
**/

/**
 * Returns YES if the action manager is suspended.
 *
 * @see suspend
 * @see resume
**/
@property (atomic, readonly) BOOL isSuspended;

/**
 * Returns the current suspendCount.
 * If the suspendCount is zero, that means isSuspended == NO;
 * if the suspendCount is non-zero, that means isSuspended == YES;
 *
 * @see suspend
 * @see resume
**/
@property (atomic, readonly) NSUInteger suspendCount;

/**
 * Increments the suspendCount by 1.
 *
 * @return
 *   The new suspend count.
**/
- (NSUInteger)suspend;

/**
 * This method operates the same as invoking the suspend method the given number of times.
 * That is, it increments the suspend count by the given number.
 *
 * @return
 *   The new suspend count.
 *
 * @see suspend
 * @see suspendCount
**/
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement;

/**
 * See the suspend method for a description of the suspend/resume architecture.
 *
 * @return
 *   The new suspend count.
**/
- (NSUInteger)resume;

@end

NS_ASSUME_NONNULL_END
