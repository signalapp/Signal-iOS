#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionConnection.h"

#import "YapDatabaseViewChange.h"
#import "YapDatabaseViewMappings.h"
#import "YapDatabaseViewRangeOptions.h"

@class YapDatabaseView;

NS_ASSUME_NONNULL_BEGIN


@interface YapDatabaseViewConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseView *parent;

/**
 * Want to easily animate a tableView or collectionView when the view changes?
 * Want an exact list of changes that happend to the view?
 *
 * You're in luck!
 *
 * Here's an overview of how it works:
 *
 * - (void)yapDatabaseModified:(NSNotification *)notification
 * {
 *     // Jump to the most recent commit.
 *     // End & Re-Begin the long-lived transaction atomically.
 *     // Also grab all the notifications for all the commits that I jump.
 *     NSArray *notifications = [roDatabaseConnection beginLongLivedReadTransaction];
 *
 *     // What changed in my tableView?
 *
 *     NSArray *sectionChanges = nil;
 *     NSArray *rowChanges = nil;
 * 
 *     [[databaseConnection extension:@"sales"] getSectionChanges:&sectionChanges
 *                                                     rowChanges:&rowChanges
 *                                               forNotifications:notifications
 *                                                   withMappings:mappings];
 *
 *     if ([sectionChanges count] == 0 && [rowChanges count] == 0)
 *     {
 *         // There aren't any changes that affect our tableView!
 *         return;
 *     }
 *
 *     // Familiar with NSFetchedResultsController?
 *     // Then this should look pretty familiar
 *
 *     [self.tableView beginUpdates];
 *
 *     for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
 *     {
 *         switch (sectionChange.type)
 *         {
 *             case YapDatabaseViewChangeDelete :
 *             {
 *                 [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
 *                               withRowAnimation:UITableViewRowAnimationAutomatic];
 *                 break;
 *             }
 *             case YapDatabaseViewChangeInsert :
 *             {
 *                 [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
 *                               withRowAnimation:UITableViewRowAnimationAutomatic];
 *                 break;
 *             }
 *         }
 *     }
 *     for (YapDatabaseViewRowChange *rowChange in rowChanges)
 *     {
 *         switch (rowChange.type)
 *         {
 *             case YapDatabaseViewChangeDelete :
 *             {
 *                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeInsert :
 *            {
 *                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeMove :
 *            {
 *                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeUpdate :
 *            {
 *                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *        }
 *    }
 *
 *    [self.tableView endUpdates];
 * }
**/
- (void)getSectionChanges:(NSArray<YapDatabaseViewSectionChange *> * _Nonnull * _Nullable)sectionChangesPtr
               rowChanges:(NSArray<YapDatabaseViewRowChange *> * _Nonnull * _Nullable)rowChangesPtr
         forNotifications:(NSArray<NSNotification *> *)notifications
             withMappings:(YapDatabaseViewMappings *)mappings;

/**
 * A simple YES/NO query to see if the view changed at all, inclusive of all groups.
**/
- (BOOL)hasChangesForNotifications:(NSArray<NSNotification *> *)notifications;

/**
 * A simple YES/NO query to see if a particular group within the view changed at all.
**/
- (BOOL)hasChangesForGroup:(NSString *)group inNotifications:(NSArray<NSNotification *> *)notifications;

/**
 * A simple YES/NO query to see if any of the given groups within the view changed at all.
**/
- (BOOL)hasChangesForAnyGroups:(NSSet<NSString *> *)groups inNotifications:(NSArray<NSNotification *> *)notifications;

/**
 * This method provides a rough estimate of the size of the change-set.
 * 
 * There may be times when a huge change-set overloads the system.
 * For example, imagine that 10,000 items were added to the view.
 *
 * Such a large change-set will likely take a bit longer to process via
 * the getSectionChanges:rowChanges:forNotifications:withMappings: method.
 * Not only that, but once you have the large arrays of sectionChanges & rowChanges,
 * feeding them into the tableView / collectionView can potentially bog down the system
 * while it attempts to calculate and perform the necessary animations.
 * 
 * This method is very very fast, and simply returns a sum of the "raw" changes.
 *
 * By "raw" we mean that it includes each individual change to the view, without any processing.
 * For example, if an item was deleted from one group, and inserted into another,
 * then this represents 2 raw changes. During formal processing, these two raw operations
 * would be consolidated into a single move operation.
 * Also note that this method doesn't take a mappings parameter.
 * So the sum of all raw changes may include things that would be filtered out during formal
 * processing due to group restrictions or range restrictions of the mappings.
 * 
 * However, this method is not intended to be precise.
 * It is intended to be fast, and to provide a rough estimate that you might use to
 * skip a potentially expensive operation.
 * 
 * Example:
 * 
 * - (void)yapDatabaseModified:(NSNotification *)notification
 * {
 *     NSArray *notifications = [databaseConnection beginLongLivedReadTransaction];
 *     
 *     NSUInteger sizeEstimate = [[databaseConnection ext:@"myView"] numberOfRawChangesForNotifications:notifications];
 *     if (sizeEstimate > 150)
 *     {
 *         // Looks like a huge changeset, so let's just reload the tableView (faster)
 *         
 *         // We're not going to call getSectionChanges:rowChanges:forNotifications:withMappings:.
 *         // We don't need to know the sectionChanges & rowChanges.
 *         // But we do need to move our mappings to the latest commit,
 *         // so that it matches our databaseConnections.
 *         // We can take a shortcut to do this, and simply tell it to "refresh" using our databaseConnection.
 *         [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *             [mappings updateWithTransaction:transaction];
 *         }];
 *         
 *         // And then we can reload our tableView, and return
 *         [tableView reloadData];
 *         return;
 *     }
 *
 *     // Normal code stuff
 * 
 *     NSArray *sectionChanges = nil;
 *     NSArray *rowChanges = nil;
 *     [[databaseConnection ext:@"myView"] getSectionChanges:&sectionChanges
 *                                                rowChanges:&rowChanges
 *                                          forNotifications:notifications
 *                                              withMappings:mappings];
 *
 *     // Normal animation code goes here....
 * }
**/
- (NSUInteger)numberOfRawChangesForNotifications:(NSArray<NSNotification *> *)notifications;

@end

NS_ASSUME_NONNULL_END
