#import <Foundation/Foundation.h>

typedef enum {
	YapDatabaseViewChangeInsert = 1,
	YapDatabaseViewChangeDelete = 2,
	YapDatabaseViewChangeMove   = 3,
	YapDatabaseViewChangeUpdate = 4,
	
} YapDatabaseViewChangeType;

typedef enum {
	YapDatabaseViewChangeColumnObject   = 1 << 0, // 0001
	YapDatabaseViewChangeColumnMetadata = 1 << 1, // 0010
	
} YapDatabaseViewChangeColumn;


/**
 * YapDatabaseViewChange is designed to help facilitate animations to tableViews and collectionsViews.
 * 
 * In addition to the documentation available in the header files,
 * you may also wish to read the wiki articles online,
 * which are designed to give you an overview of the various technologies available.
 * 
 * General information about setting up and using Views:
 * https://github.com/yaptv/YapDatabase/wiki/Views
 * 
 * General information about technologies which integrate with Views:
 * https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
 * https://github.com/yaptv/YapDatabase/wiki/YapDatabaseModifiedNotification
**/

@interface YapDatabaseViewSectionChange : NSObject <NSCopying>

/**
 * The type will be either Insert or Delete
 *
 * @see YapDatabaseViewChangeType
**/
@property (nonatomic, readonly) YapDatabaseViewChangeType type;

/**
 * The section index.
 * 
 * If the type is YapDatabaseViewChangeDelete, then this represents the originalIndex of the section (pre-animation).
 * If the type is YapDatabaseViewChangeInsert, then this represents the finalIndex of the section (post-animation).
**/
@property (nonatomic, readonly) NSUInteger index;

/**
 * The corresponding group for the section.
**/
@property (nonatomic, readonly) NSString *group;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewRowChange : NSObject <NSCopying>

/**
 * The type will be one of: Insert, Delete, Move or Update
 * 
 * @see YapDatabaseViewChangeType
**/
@property (nonatomic, readonly) YapDatabaseViewChangeType type;

/**
 * The column property is a bitflag representing the column(s) that were changed for corresponding row in the database.
 *
 * This may be useful for various optimizations.
 * For example, if your view depends only on the object, then you skip updates when the metadata is changed.
 * 
 * if (change.modifiedColumns & YapDatabaseViewChangeColumnObject) {
 *     // object changed, update view
 * }
 * else {
 *     // only the metadata changed, we can skip updating the view
 * }
 * 
 * @see YapDatabaseViewChangeColumn
**/
@property (nonatomic, readonly) int modifiedColumns;

/**
 * The indexPath & newIndexPath are available after
 * you've invoked changesForNotifications:withGroupToSectionMappings:.
 * 
 * @see YapDatabaseConnection changesForNotifications:withGroupToSectionMappings:
 * @see YapCollectionsDatabaseConnection changesForNotifications:withGroupToSectionMappings:
 * 
 * These properties are designed to help facilitate animations to tableViews and collectionsViews.
 * 
 * Recall that a view has no concept of sections.
 * That is, a view has groups not sections.
 * A group is a string, and a section is just a number.
 * 
 * Using groups allows a view to be more dynamic.
 * Your view may contain dozens of groups,
 * but a particular tableView within your app may only display a few of the groups.
 * 
 * For example, you may a view which groups all products in a grocery store by department (produce, deli, bakery),
 * sorting products by price. Using this view you can easily bring up a table view which displays only
 * a few departments such as: liquor, wine, beer.
 * 
 * In this example:
 * - Section 0 = liquor
 * - Section 1 = wine
 * - Section 2 = beer
 *
 * NSDictionary *mappings = @{ @"liquor":@(0), @"wine":@(1), @"beer":@(2) };
 *
 * NSArray *notifications = [databaseConnection beginLongLivedReadTransaction];
 * NSArray *changes = [databaseConnection changesForNotifications:notification
 *                                     withGroupToSectionMappings:mappings];
 *
 * The indexPath and newIndexPath properties are modeled after:
 * NSFetchedResultsControllerDelegate controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:
 * 
 * - indexPath is non-nil for types    : Delete, Move, Update
 * - newIndexPath is non-nil for types : Insert, Move
 * 
 * Template code:
 *
 * [self.tableView beginUpdates];
 *
 * for (YapDatabaseViewChange *change in changes)
 * {
 *     switch (change.type)
 *     {
 *         case YapDatabaseViewChangeDelete :
 *         {
 *             [self.tableView deleteRowsAtIndexPaths:@[ change.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeInsert :
 *         {
 *             [self.tableView insertRowsAtIndexPaths:@[ change.newIndexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeMove :
 *         {
 *             [self.tableView deleteRowsAtIndexPaths:@[ change.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             [self.tableView insertRowsAtIndexPaths:@[ change.newIndexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeUpdate :
 *         {
 *             [self.tableView reloadRowsAtIndexPaths:@[ change.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *     }
 * }
 *
 * [self.tableView endUpdates];
**/
@property (nonatomic, readonly) NSIndexPath *indexPath;
@property (nonatomic, readonly) NSIndexPath *newIndexPath;

/**
 * The "original" values represent the location of the changed item
 * at the BEGINNING of the read-write transaction(s).
 *
 * The "final" values represent the location of the changed item
 * at the END of the read-write transaction(s).
**/

@property (nonatomic, readonly) NSUInteger originalIndex;
@property (nonatomic, readonly) NSUInteger finalIndex;

@property (nonatomic, readonly) NSUInteger originalSection;
@property (nonatomic, readonly) NSUInteger finalSection;

@property (nonatomic, readonly) NSString *originalGroup;
@property (nonatomic, readonly) NSString *finalGroup;

@end
