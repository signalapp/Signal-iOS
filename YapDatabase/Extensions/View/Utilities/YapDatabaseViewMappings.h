#import <Foundation/Foundation.h>
#import "YapDatabaseViewRangeOptions.h"

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
 * A group/section can either be "static" or "dynamic".
 * 
 * A dynamic section automatically disappears if it becomes empty.
 * A static section is always visible, regardless of its item count.
 * 
 * By default all groups/sections are static.
 * You can enable dynamic sections on a per-group basis (just for certain sections) or for all groups (all sections).
 * 
 * If you enable dynamic sections, be sure to use the helper methods available in this class.
 * This will drastically simplify things for you.
 * For example:
 * 
 * Let's say you have 3 groups: @[ @"wine", @"liquor", @"beer" ]
 * You've enabled dynamic sections for all groups.
 * Section 0 refers to what group?
 * 
 * The answer depends entirely on the item count per section.
 * If "wine" is empty, but "liquor" isn't, then section zero is "liquor".
 * If "wine" and "liquor" are empty, but "beer" isn't, then section zero is "beer".
 * 
 * But you can simply do this to get the answer:
 *
 * NSString *group = [mappings groupForSection:indexPath.section];
 *
 * @see numberOfSections
 * @see groupForSection:
 * @see visibleGroups
 * 
 * The mappings object is used with:
 *
 * - YapDatabaseViewConnection getSectionChanges:rowChanges:forNotifications:withMappings:
 * - YapCollectionsDatabaseViewConnection getSectionChanges:rowChanges:forNotifications:withMappings:
 * 
 * If all your sections are static, then you won't ever get any section changes.
 * But if you have one or more dynamic sections, then be sure to process the section changes.
 * As the dynamic sections disappear & re-appear, the proper section changes will be emitted.
 *
 * By DEFAULT, all groups/sections are STATIC.
 * You can configure this per group, or all-at-once.
**/

- (BOOL)isDynamicSectionForAllGroups;
- (void)setIsDynamicSectionForAllGroups:(BOOL)isDynamic;

- (BOOL)isDynamicSectionForGroup:(NSString *)group;
- (void)setIsDynamicSection:(BOOL)isDynamic forGroup:(NSString *)group;

/**
 * You can use the YapDatabaseViewRangeOptions class to configure a "range" that you would
 * like to restrict your tableView / collectionView to.
 * 
 * Two types of ranges are supported:
 * 
 * 1. Fixed ranges.
 *    This is similar to using a LIMIT & OFFSET in a typical sql query.
 * 
 * 2. Flexible ranges.
 *    These allow you to specify an initial range, and allow it to grow and shrink.
 * 
 * The YapDatabaseViewRangeOptions header file has a lot of documentation on
 * setting up and configuring range options.
 * 
 * One of the best parts of using rangeOptions is that you get animations for free.
 * For example:
 * 
 * Say you have view that sorts items by sales rank.
 * You want to display a tableView that displays the top 20 best-sellers. Simple enough so far.
 * But you want the tableView to automatically update throughout the day as sales are getting processed.
 * And you want the tableView to automatically animate any changes. (No wimping out with reloadData!)
 * You can get this with only a few lines of code using range options.
 * 
 * Note that if you're using range options, then the indexPaths in your UI might not match up directly
 * with the indexes in the view's group. You can use the various mapping methods in this class
 * to automatically handle all that.
**/

- (void)setRangeOptions:(YapDatabaseViewRangeOptions *)rangeOpts forGroup:(NSString *)group;
- (YapDatabaseViewRangeOptions *)rangeOptionsForGroup:(NSString *)group;

- (void)removeRangeOptionsForGroup:(NSString *)group;

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
 * This method properly takes into account dynamic groups.
 *
 * If the section is out-of-bounds, returns nil.
**/
- (NSString *)groupForSection:(NSUInteger)section;

/**
 * Returns the visible section number for the visible group.
 * If the group is NOT visible, returns NSNotFound.
 *
 * If a group is empty (numberOfItemsInGroup == 0), AND the group is dynamic, then it becomes invisible.
 * Only in this case would this method return NSNotFound.
**/
- (NSUInteger)sectionForGroup:(NSString *)group;

/**
 * The visibleGroups property returns the current sections setup.
 * That is, it only contains the visible groups that are being represented as sections in the view.
 *
 * If all sections are static, then visibleGroups will always be the same all allGroups.
 * However, if one or more sections are dynamic, then the visible groups may be a subset of allGroups.
 * 
 * Dynamic groups/sections automatically "disappear" if/when they become empty.
**/
- (NSArray *)visibleGroups;

@end
