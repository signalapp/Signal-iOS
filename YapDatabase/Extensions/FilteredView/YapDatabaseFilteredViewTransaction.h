#import <Foundation/Foundation.h>

#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseFilteredViewTypes.h"
#import "YapDatabaseFilteredView.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseFilteredViewTransaction : YapDatabaseViewTransaction

// This class extends YapDatabaseViewTransaction.
//
// Please see YapDatabaseViewTransaction.h

@end

#pragma mark -

@interface YapDatabaseFilteredViewTransaction (ReadWrite)

/**
 * This method allows you to change the filterBlock on-the-fly.
 * 
 * When you do so, the extension will emit the smallest change-set possible.
 * That is, it does NOT clear the view and start from scratch.
 * Rather it performs a quick in-place update.
 * The end result is a minimal change-set that looks nice for tableView / collectionView animations.
 * 
 * For example, in Apple's phone app, in the Recents tab, one can switch between "all" and "missed" calls.
 * Tapping the "missed" button smoothly animates away all non-red rows. It looks great.
 * You can get the same effect by using a YapDatabaseFilteredView,
 * and swapping in/out a filterBlock to allow/disallow non-missed calls.
 *
 * Note: You must pass a different versionTag, or this method does nothing.
**/
- (void)setFiltering:(YapDatabaseViewFiltering *)filtering
          versionTag:(nullable NSString *)tag;

@end

NS_ASSUME_NONNULL_END
