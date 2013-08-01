#import <Foundation/Foundation.h>

@class YapAbstractDatabaseTransaction;

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
 * YapDatabaseViewMappings helps you map from groups to sections.
 * Let's take a look at a concrete example:
 * 
 * Say you have a database full of items for sale in a grocery store.
 * You have a view which sorts the items alphabetically, grouped by department.
 * There are many different departments (produce, bakery, dairy, wine, etc).
 * But you want to display a table view that contains only a few departments: (wine, liquor, beer).
 * 
 * This class allows you to specify that you want:
 * - section 0 = wine
 * - section 1 = liquor
 * - section 2 = beer
 * 
 * From this starting point, the class helps you map from section to group, and vice versa.
 * Plus it can properly take into account empty sections. For example, if there are no items
 * for sale in the liquor department then it can automatically move beer to section 1 (optional).
 * 
 * But the primary purpose of this class has to do with assisting in animating changes to your view.
 * In order to provide the proper animation instructions to your tableView or collectionView,
 * the database layer needs to know a little about how you're setting things up.
 * 
 * Using the example above, we might have code that looks something like this:
 * 
 * - (void)viewDidLoad
 * {
 *     // Freeze our connection for use on the main-thread.
 *     // This gives us a stable data-source that won't change until we tell it to.
 *
 *     [databaseConnection beginLongLivedReadTransaction];
 *
 *     // The view may have a whole bunch of groups.
 *     // In our example, the view contains a group for every department in the grocery store.
 *     // We only want to display the alcohol related sections in our tableView.
 *     
 *     NSArray *groups = @[@"wine", @"liquor", @"beer"];
 *     mappings = [[YapDatabaseViewMappings alloc] initWithGroups:groups view:@"order"];
 * 
 *     // There are several ways in which we can further configure the mappings.
 *     // You would configure it however you want.
 *     
 *     mappings.allowsEmptySections = YES;
 *     
 *     // Now initialize the mappings.
 *     // This will allow the mappings object to get the counts per group.
 *     
 *     [databaseConnection readWithBlock:(YapDatabaseReadTransaction *transaction){
 *         // One-time initialization
 *         [mappings updateWithTransaction:transaction];
 *     }];
 *     
 *     // And register for notifications when the database changes.
 *     // Our method will be invoked on the main-thread,
 *     // and will allow us to move our stable data-source from our existing state to an updated state.
 *
 *     [[NSNotificationCenter defaultCenter] addObserver:self
 *                                              selector:@selector(yapDatabaseModified:)
 *                                                  name:YapDatabaseModifiedNotification
 *                                                object:databaseConnection.database];
 * }
 *
 * - (void)yapDatabaseModified:(NSNotification *)notification
 * {
 *     // End & Re-Begin the long-lived transaction atomically.
 *     // Also grab all the notifications for all the commits that I jump.
 *     
 *     NSArray *notifications = [databaseConnection beginLongLivedReadTransaction];
 * 
 *     // Process the notification(s),
 *     // and get the changeset as it applies to me, based on my view and my mappings setup.
 * 
 *     NSArray *sectionChanges = nil;
 *     NSArray *rowChanges = nil;
 *     
 *     [[databaseConnection ext:@"order"] getSectionChanges:&sectionChanges
 *                                               rowChanges:&rowChanges
 *                                         forNotifications:notifications
 *                                             withMappings:mappings];
 *     
 *     // No need to update mappings.
 *     // The above method did it automatically.
 *     
 *     if ([sectionChanges count] == 0 & [rowChanges count] == 0)
 *     {
 *         // Nothing has changed that affects our tableView
 *         return;
 *     }
 *
 *     // Now it's time to process the changes.
 *     // 
 *     // Note: Because we explicitly told the mappings to allowEmptySections,
 *     // there won't be any section changes. If we had instead set allowEmptySections to NO,
 *     // then there might be section deletions & insertions as sections become empty & non-empty.
 *
 *     [self.tableView beginUpdates];
 *     
 *     for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
 *     {
 *         // ... (see https://github.com/yaptv/YapDatabase/wiki/Views )
 *     }
 *     
 *     for (YapDatabaseViewRowChange *rowChange in rowChanges)
 *     {
 *         // ... (see https://github.com/yaptv/YapDatabase/wiki/Views )
 *     }
 *
 *     [self.tableView endUpdates];
 * }
 * 
 * - (NSInteger)numberOfSectionsInTableView:(UITableView *)sender
 * {
 *     // We can use the cached information in the mappings object.
 *     // 
 *     // This comes in handy if my sections are dynamic,
 *     // and automatically come and go as individual sections become empty & non-empty.
 *
 *     return [mappings numberOfSections];
 * }
 * 
 * - (NSInteger)tableView:(UITableView *)sender numberOfRowsInSection:(NSInteger)section
 * {
 *     // We can use the cached information in the mappings object.
 *
 *     return [mappings numberOfItemsInSection:section];
 * }
 * 
 * - (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
 * {
 *     // If my sections are dynamic (they automatically come and go as individual sections become empty & non-empty),
 *     // then I can easily use the mappings object to find the appropriate group.
 *     
 *     NSString *group = [mappings groupForSection:indexPath.section];
 *
 *     __block id object = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *         
 *         object = [[transaction ext:@"view"] objectAtIndex:indexPath.row inGroup:group];
 *     }];
 * 
 *     // configure and return cell...
 * }
 *
 * @see YapDatabaseConnection getSectionChanges:rowChanges:forNotifications:withMappings:
 * @see YapCollectionsDatabaseConnection getSectionChanges:rowChanges:forNotifications:withMappings:
**/

typedef enum {
	YapDatabaseViewBeginning = 0, // index == 0
	YapDatabaseViewEnd       = 1, // index == last
	
} YapDatabaseViewPin;


@interface YapDatabaseViewMappings : NSObject <NSCopying>

/**
 * Initializes a new mappings object.
 * 
 * @param allGroups
 *     The ordered array of group names.
 *     From the example above, this would be @[ @"wine", @"liquor", @"beer" ]
 * 
 * @param registeredViewName
 *     This is the name of the view, as you registered it with the database system.
**/
- (id)initWithGroups:(NSArray *)allGroups
				view:(NSString *)registeredViewName;


#pragma mark Accessors

/**
 * The allGroups property returns the groups that were passed in the init method.
 * That is, all groups, whether currently visible or non-visible.
 * 
 * @see visibleGroups
**/
@property (nonatomic, copy, readonly) NSArray *allGroups;

/**
 * The registeredViewName that was passed in the init method.
**/
@property (nonatomic, copy, readonly) NSString *view;


#pragma mark Configuration

/**
 * What happens if a group/section has zero items?
 * Do you want the section to disappear from the view?
 * Or do you want the section to remain visible as an empty section?
 * 
 * If allowsEmptySections is set to NO, then sections that have zero items automatically get removed.
 * If allowsEmptySections is set to YES, then sections that have zero items remain visible.
 *
 * The default value (for all groups) is NO.
 * You can configure this per group, or all-at-once.
**/

- (BOOL)allowsEmptySectionForAllGroups;
- (void)setAllowsEmptySectionForAllGroups:(BOOL)globalAllowsEmptySections;

- (BOOL)allowsEmptySectionForGroup:(NSString *)group;
- (void)setAllowsEmptySection:(BOOL)allowsEmptySection forGroup:(NSString *)group;

/**
 * TODO
 * 
 * Add ability to specify "ranges" for particular groups.
 * Examples:
 * 
 * - Specify a range to see only top 20 in "sales" group.
 *   If new entries rise to the top, the mappings ensure that those that have fallen below the threshold
 *   have proper delete changes emitted.
 *
 * - Specify a min key to see only that item and items after it in the view.
 *   Similar to Apple's SMS messaging app, you start with the most recent 50 items,
 *   but allow new items to be added to the view.
 * 
 * - Max key works the same as min key, but is for when your view is sorted in the other direction.
 * 
 * We also need translation methods, to go from tableView.indexPath to view.index ...
**/

- (void)setRange:(NSRange)range
            hard:(BOOL)isHardRange
        pinnedTo:(YapDatabaseViewPin)pinnedToBeginningOrEnd
        forGroup:(NSString *)group;

- (void)removeRangeOptionsForGroup:(NSString *)group;

- (BOOL)getRange:(NSRange *)rangePtr
            hard:(BOOL *)isHardRangePtr
        pinnedTo:(YapDatabaseViewPin *)pinnedToPtr
        forGroup:(NSString *)group;

/**
 * TODO
**/

//- (BOOL)isReversedForGroup:(NSString *)group;
//- (void)setIsReversed:(BOOL)isReversed forGroup:(NSString *)group;

#pragma mark Initialization & Updates

/**
 * You have to call this method to initialize the mappings.
 * This method uses the given transaction to fetch and cache the counts for each group.
 * 
 * This class is designed to be used with the method getSectionChanges:rowChanges:forNotifications:withMappings:.
 * That method needs the 'before' & 'after' snapshot of the mappings in order to calculate the proper changeset.
 * In order to get this, it automatically invokes this method.
 *
 * Thus you only have to manually invoke this method once.
 * Aftewards, it should be invoked for you.
 * 
 * Please see the example code above.
**/
- (void)updateWithTransaction:(YapAbstractDatabaseTransaction *)transaction;

/**
 * Returns the snapshot of the last time the mappings were initialized/updated.
 * 
 * This method is primarily for internal use.
 * When the changesets are being calculated from the notifications & mappings,
 * this property is consulted to ensure the mappings match the notifications.
 *
 * Everytime the updateWithTransaction method is invoked,
 * this property will be set to transaction.abstractConnection.snapshot.
 *
 * If never initialized/updated, the snapshot will be UINT64_MAX.
 * 
 * @see YapAbstractDatabaseConnection snapshot
**/
@property (nonatomic, readonly) uint64_t snapshotOfLastUpdate;

#pragma mark Getters

/**
 * Returns the actual number of sections.
 * This number may be less than the full list of groups (unless allowsEmptySections == YES).
**/
- (NSUInteger)numberOfSections;

/**
 * Returns the number of items in the given section.
 * @see groupForSection
**/
- (NSUInteger)numberOfItemsInSection:(NSUInteger)section;

/**
 * Returns the number of items in the given group.
 * 
 * This is the cached value from the last time one of the following methods was invoked:
 * - updateWithTransaction:
 * - changesForNotifications:withMappings:
**/
- (NSUInteger)numberOfItemsInGroup:(NSString *)group;

/**
 * Returns the group for the given section.
 * This method properly takes into account empty groups.
 *
 * If the section is out-of-bounds, returns nil.
 * 
 * @see allowsEmptySections
**/
- (NSString *)groupForSection:(NSUInteger)section;

/**
 * If the group is empty, and allowsEmptySections is true, returns NSNotFound.
 * 
 * @see allowsEmptySections
**/
- (NSUInteger)sectionForGroup:(NSString *)group;

/**
 * The visibleGroups property returns the current sections setup.
 * That is, it only contains the groups that are being represented as sections in the view.
 *
 * This may be a subset of allGroups, representing those groups that have 1 or more items.
 *
 * @see allGroups
**/
- (NSArray *)visibleGroups;

@end
