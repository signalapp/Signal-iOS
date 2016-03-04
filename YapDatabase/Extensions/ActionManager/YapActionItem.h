#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YapActionItemBlock)(NSString *collection, NSString *key, id object, _Nullable id metadata);

/**
 * This class is used by the YapDatabaseActionManager,
 * and any model object(s) that need to interact with it.
 * 
 * A YapActionItem encompasses a majority of the logic required to track
 * when a particular action should occur concerning a particular model object.
**/
@interface YapActionItem : NSObject <NSCopying>

/**
 * See the description for each individual property below.
**/

- (instancetype)initWithIdentifier:(NSString *)identifier
                              date:(nullable NSDate *)date
                      retryTimeout:(NSTimeInterval)retryTimeout
                  requiresInternet:(BOOL)requiresInternet
                             block:(YapActionItemBlock)block;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              date:(nullable NSDate *)date
                      retryTimeout:(NSTimeInterval)retryTimeout
                  requiresInternet:(BOOL)requiresInternet
                             queue:(nullable dispatch_queue_t)queue
                             block:(YapActionItemBlock)block;

/**
 * The identifier should uniquely identify the activity.
 * It only needs to be unique within the context of the parent object.
 * That is, the YapDatabaseActionManager knows who the parent is for all YapActionItem instances.
 * 
 * For example:
 * The MyUser object has a refreshDate property.
 * An associated YapActionItem will be created in order to refresh the user's info from the server.
 * The identifier could simply be @"refresh".
**/
@property (nonatomic, copy, readonly) NSString *identifier;

/**
 * Represents the date at which the action should be performed.
 * 
 * If no date was given in the init method,
 * then the date will be [NSDate dateWithTimeIntervalSinceReferenceDate:0.0].
**/
@property (nonatomic, strong, readonly) NSDate *date;

/**
 * It is the responsibility of the block to update the associated object in the database
 * in such a manner that the YapActionItem is deleted or has its date changed.
 * 
 * Example 1:
 *   The MyUser has a needsUploadAvatar property.
 *   When set to YES, an associated YapActionItem (with identifier "uploadAvatar") will be created in order to
 *   invoke the uploadAvatar method. When the upload succeeds, it should set the needsUploadAvatar property to NO.
 *   Which, in turn, will result in the MyUser not creating a YapActionItem (with identifier "uploadAvatar").
 * 
 * Example 2:
 *   The MyUser object has a refreshDate property.
 *   An associated YapActionItem (with identifier "refresh") will be created in order to invoke the refresh method.
 *   When the refresh succeeds, it should update the refreshDate to some point in the future.
 *   Which, in turn, will result in the MyUser creating a modified YapActionItem (same identifier, but different date).
**/
@property (nonatomic, assign, readonly) NSTimeInterval retryTimeout;

/**
 * Should be YES if the action requires internet connectivity in order to complete.
 * If so, then the DatabaseActionManager won't bother invoking the block
 * until internet connectivity appears to be available.
 * 
 * This prevents a network request from constantly failing (when there's no internet available),
 * and constantly awaiting the retryTimeout before attempting again.
 * 
 * In other words, when the network is down, the DatabaseActionManager will simply queue
 * all items that require internet. And when the network comes back up, it will dequeue them.
**/
@property (nonatomic, assign, readonly) BOOL requiresInternet;

/**
 * The YapActionItemBlock will be executed on this queue via dispatch_async.
 * 
 * If no queue is specified, a global queue is automatically used.
 * Specifically: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
**/
@property (nonatomic, strong, readonly, nullable) dispatch_queue_t queue;

/**
 * The block that gets executed (at the proper time).
 * The block will be executed (via dispatch_async) on the designated 'queue'.
 * 
 * Important: This block should NOT retain 'self'.
 * The block should rely upon the various parameters in order to get its information.
 * 
 * @see queue
**/
@property (nonatomic, strong, readonly) YapActionItemBlock block;


/**
 * Compares self.date with the atDate parameter.
 * 
 * @param atDate
 *   The date to compare with.
 *   If nil, the current date is automatically used.
 * 
 * @return
 *   Returns NO if self.date is after atDate (comparitively in the future).
 *   Returns YES otherwise (comparitively in the past or present).
**/
- (BOOL)isReadyToStartAtDate:(nullable NSDate *)atDate;

/**
 * Two YapActionItems are considered to be the same if they have the same identifier & date.
 * If the identifiers are different, they are obviously different tasks.
 * If the dates are different, then they are also considered different.
 * 
 * Remember, it is common to have recurring operations, such as a refresh operation.
 * Thus, when a refresh completes, it automatically schedules another refresh, but at a later date.
 * This would result in two YapActionItems with the same identifier, but different dates.
 * YapDatabaseActionManager would then consider these two items to be different.
 * The old item (same identifier, previous date in the past) would be considered complete,
 * because it is no longer being represented in the 'yapActionItems' array.
 * The new item (same identifier, new date in the future) would be considered new, and will be scheduled.
**/
- (BOOL)hasSameIdentifierAndDate:(YapActionItem *)another;

/**
 * Used for sorting items based on their date.
 * If two items have the exact same date, the comparison will fallback to comparing identifiers.
**/
- (NSComparisonResult)compare:(YapActionItem *)another;

@end

NS_ASSUME_NONNULL_END

