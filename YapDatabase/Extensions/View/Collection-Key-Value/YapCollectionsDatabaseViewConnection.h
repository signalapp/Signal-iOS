#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"
#import "YapDatabaseViewChange.h"

@class YapCollectionsDatabaseView;

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/Views
 *
 *
 * As a extension, YapCollectionsDatabaseViewConnection is automatically created by YapCollectionsDatabaseConnnection.
 * You can access this object via:
 *
 * [databaseConnection extension:@"myRegisteredViewName"]
 *
 * @see YapCollectionsDatabaseView
 * @see YapCollectionsDatabaseViewTransaction
**/
@interface YapCollectionsDatabaseViewConnection : YapAbstractDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapCollectionsDatabaseView *view;

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
 *     NSDictionary *mappings = @{ @"bestSellers" : @(0) };
 *     NSArray *changes = [[databaseConnection extension:@"sales"] operationsForNotifications:notifications
 * 	                                                        withGroupToSectionMappings:mappings];
 *     if ([changes count] == 0)
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
 *     for (YapDatabaseViewChange *change in changes)
 *     {
 *         switch (change.type)
 *         {
 *             case YapDatabaseViewChangeDelete :
 *             {
 *                [self.tableView deleteRowsAtIndexPaths:@[ change.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeInsert :
 *            {
 *                [self.tableView insertRowsAtIndexPaths:@[ change.newIndexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeMove :
 *            {
 *                [self.tableView deleteRowsAtIndexPaths:@[ change.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                [self.tableView insertRowsAtIndexPaths:@[ change.newIndexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *            case YapDatabaseViewChangeUpdate :
 *            {
 *                [self.tableView reloadRowsAtIndexPaths:@[ change.indexPath ]
 *                                      withRowAnimation:UITableViewRowAnimationAutomatic];
 *                break;
 *            }
 *        }
 *    }
 *
 *    [self.tableView endUpdates];
 * }
**/
- (NSArray *)changesForNotifications:(NSArray *)notifications withGroupToSectionMappings:(NSDictionary *)mappings;

@end
