#import <Foundation/Foundation.h>
#import "YapCollectionKey.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, YapDatabaseViewChangeType) {
	YapDatabaseViewChangeInsert = 1,
	YapDatabaseViewChangeDelete = 2,
	YapDatabaseViewChangeMove   = 3,
	YapDatabaseViewChangeUpdate = 4,
};

typedef NS_OPTIONS(NSUInteger, YapDatabaseViewChangesBitMask) {
	YapDatabaseViewChangedObject     = 1 << 0, // 0001
	YapDatabaseViewChangedMetadata   = 1 << 1, // 0010
	YapDatabaseViewChangedDependency = 1 << 2, // 0100  (used by YapDatabaseViewMappings)
	YapDatabaseViewChangedSnippets   = 1 << 3, // 1000  (used by YapDatabaseSearchResultsView)
};

/**
 * YapDatabaseViewChange is designed to help facilitate animations to tableViews and collectionsViews.
 * 
 * In addition to the documentation available in the header files,
 * you may also wish to read the wiki articles online,
 * which are designed to give you an overview of the various technologies available.
 * 
 * General information about setting up and using Views:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
 * 
 * General information about technologies which integrate with Views:
 * https://github.com/yapstudios/YapDatabase/wiki/LongLivedReadTransactions
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseModifiedNotification
**/

@interface YapDatabaseViewSectionChange : NSObject <NSCopying>

/**
 * The type will be either:
 * - YapDatabaseViewChangeInsert or
 * - YapDatabaseViewChangeDelete
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
 * The type will be one of:
 * - YapDatabaseViewChangeInsert
 * - YapDatabaseViewChangeDelete
 * - YapDatabaseViewChangeMove
 * - YapDatabaseViewChangeUpdate
 * 
 * @see YapDatabaseViewChangeType
**/
@property (nonatomic, readonly) YapDatabaseViewChangeType type;

/**
 * The changes property is a bitmask representing what changed for the corresponding row in the database.
 *
 * There are 3 types represented in the bit mask:
 * - YapDatabaseViewChangedObject
 * - YapDatabaseViewChangedMetadata
 * - YapDatabaseViewChangedDependency
 * 
 * YapDatabaseViewChangedObject means the object was changed via setObject:forKey:inCollection:.
 *
 * YapDatabaseViewChangedMetadata means the metadata was changed.
 * This might have happend implicitly if the user invoked setObject:forKey:inCollection: (implicitly setting
 * the metadata to nil). Or explicitly if the user invoked setObject:forKey:inCollection:withMetadata: or
 * replaceMetadata:forKey:inCollection:.
 * 
 * YapDatabaseViewChangedDependency means the row was flagged due to a cell drawing dependency configuration.
 * See YapDatabaseViewMappings: setCellDrawingDependencyForNeighboringCellWithOffset:forGroup:
 * 
 * Keep in mind that this is a bitmask. So, for example, all bits might be set if
 * a row was updated, and was also flagged due to an inter-cell drawing dependency.
 *
 * This may be useful for various optimizations. For example:
 * The drawing of your cell depends only on the object.
 * However, your objects are rather large, and you're using metadata to store small subsets of the object
 * that often need to be fetched. In addition, you're keeping other information in metadata such as refresh dates
 * for pulling updates from the server. The grouping and sorting block are optimized and use only the metadata.
 * However this means that the metadata may change (due to a refresh date update),
 * when in fact the object itself didn't change.
 * So you could optimize a bit here by skipping some cell updates.
 * 
 * if (change.type == YapDatabaseViewChangeUpdate)
 * {
 *     if (change.modifiedColumns & YapDatabaseViewChangedObject) {
 *         // object changed, update cell
 *     }
 *     else {
 *         // only the metadata changed, so we can skip updating the cell
 *     }
 * }
 *
 *
 * @see YapDatabaseViewChangesBitMask
**/
@property (nonatomic, readonly) YapDatabaseViewChangesBitMask changes;

/**
 * The indexPath & newIndexPath are available after
 * you've invoked getSectionChanges:rowChanges:forNotifications:withMappings:.
 *
 * @see YapDatabaseConnection getSectionChanges:rowChanges:forNotifications:withMappings:
 * 
 * These properties are designed to help facilitate animations to tableViews and collectionsViews.
 * 
 * Recall that a view has no concept of sections.
 * That is, a view has groups not sections.
 * A group is a string, and a section is just a number.
 * 
 * Using groups allows a view to be more dynamic.
 * Your view may contain dozens of groups,
 * but a particular tableView within your app may only display a subset of the groups.
 * 
 * For example, you may have a view for displaying products in a grocery store.
 * Each product is grouped by department (e.g. produce, deli, bakery), and sorted sorted by name.
 * Using this view you can easily bring up a table view which displays only
 * a few departments such as: liquor, wine, beer.
 * 
 * In this example:
 * - Section 0 = liquor
 * - Section 1 = wine
 * - Section 2 = beer
 *
 * NSArray *groups = @{ @"liquor":@(0), @"wine":@(1), @"beer":@(2) };
 * YapDatabaseMappings *mappings = [YapDatabaseViewMappings mappingsWithGroups:groups view:@"order"];
 *
 * The mappings are then used to "map" between the 'groups in the view' and 'items in the table'.
 * 
 * Mappings can provide a lot of additional functionality as well.
 * For example, you can configure the mappings to only display a particular range within a group.
 * This is similar to a LIMIT & OFFSET in SQL.
 * This is the tip of the iceberg. See YapDatabaseViewMappings.h for more info.
 *
 * In order to animate changes to your tableView or collectionView, you eventually do something like this:
 * 
 * NSArray *sectionChanges = nil;
 * NSArray *rowChanges = nil;
 * [databaseConnection getSectionChanges:&sectionChanges
 *                            rowChanges:&rowChanges
 *                      forNotifications:notifications
 *                          withMappings:mappings];
 * 
 * This gives you a list of changes as they affect your tableView / collectionView.
 *
 * The indexPath and newIndexPath properties are modeled after:
 * NSFetchedResultsControllerDelegate controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:
 * 
 * - indexPath represents the ORIGINAL indexPath for the row.
 *   It is non-nil for the following types : Delete, Move, Update.
 *   (And nil for insert since there was no original indexPath.)
 *
 * - newIndexPath represents the FINAL indexPath for the row.
 *   It is non-nil for the following types : Insert, Move.
 *   (And nil for delete since there is no final indexPath.)
 *   (And nil for update since that's how NSFetchedResultsController works,
 *    and thus how existing code might expect it to work.)
 * 
 * Once you have the sectionChanges & rowChanges, you can animate your tableView very simply like so:
 * 
 * PS - For a FULL CODE EXAMPLE, see the wiki:
 * https://github.com/yapstudios/YapDatabase/wiki/Views#wiki-animating_updates_in_tableviews_collectionviews
 *
 * if ([sectionChanges count] == 0 & [rowChanges count] == 0)
 * {
 *     // Nothing has changed that affects our tableView
 *     return;
 * }
 *
 * // Familiar with NSFetchedResultsController?
 * // Then this should look pretty familiar
 *
 * [self.tableView beginUpdates];
 *
 * for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
 * {
 *     switch (sectionChange.type)
 *     {
 *         case YapDatabaseViewChangeDelete :
 *         {
 *             [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
 *                           withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeInsert :
 *         {
 *             [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
 *                           withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *     }
 * }
 *
 * for (YapDatabaseViewRowChange *rowChange in rowChanges)
 * {
 *     switch (rowChange.type)
 *     {
 *         case YapDatabaseViewChangeDelete :
 *         {
 *             [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeInsert :
 *         {
 *             [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeMove :
 *         {
 *             [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationAutomatic];
 *             break;
 *         }
 *         case YapDatabaseViewChangeUpdate :
 *         {
 *             [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
 *                                   withRowAnimation:UITableViewRowAnimationNone];
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
 * 
 * This information also available in another form via the indexPath & newIndexPath properties.
**/

@property (nonatomic, readonly) NSUInteger originalIndex;
@property (nonatomic, readonly) NSUInteger finalIndex;

@property (nonatomic, readonly) NSUInteger originalSection;
@property (nonatomic, readonly) NSUInteger finalSection;

@property (nonatomic, readonly) NSString *originalGroup;
@property (nonatomic, readonly) NSString *finalGroup;

/**
 * Gives you the {collection,key} tuple that caused the row change.
 * 
 * Please note that this information is not always available.
 * In particular, it may not be available if:
 *
 * - the rowChange was due solely to a dependency (YapDatabaseViewChangedDependency)
 * - the rowChange was due solely to satisfy a range constraint (YapDatabaseViewRangeOptions)
 * - the rowChange was due to the database being cleared (removeAllObjectsInAllCollections)
 * 
 * However, it will be available for the most important situation,
 * which is when a particular item from the database has been removed. (YapDatabaseViewChangeDelete)
 * 
 * In other situations (YapDatabaseViewChangeInsert, YapDatabaseViewChangeUpdate, YapDatabaseViewChangeMove)
 * you'd be able to fetch the corresponding information directly from the View. For example:
 * 
 * for (YapDatabaseViewRowChange *rowChange in rowChanges)
 * {
 *     switch (rowChange.type)
 *     {
 *         // ...
 *         case YapDatabaseViewChangeInsert :
 *         {
 *             // What changed exactly ?
 *             __block NSString *collection = nil;
 *             __block NSString *key = nil;
 *             [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *                 [[transaction ext:@"view"] getKey:&key
 *                                        collection:&collection
 *                                       atIndexPath:rowChange.newIndexPath
 *                                      withMappings:mappings];
 *             // ...
 *         }
 *         // ....
 *     }
 * }
 * 
 * However, you'll notice that you wouldn't be able to fetch the collection/key for a deleted item,
 * because the rowChange.indexPath is no longer valid for the current state of the database/view.
 *
 * And thus that information is available via this property, should you ever need it.
**/

@property (nonatomic, readonly) YapCollectionKey *collectionKey;

@end

NS_ASSUME_NONNULL_END
