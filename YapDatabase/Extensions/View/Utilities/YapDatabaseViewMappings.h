#import <Foundation/Foundation.h>
#import "YapDatabaseViewRangeOptions.h"

@class YapDatabaseReadTransaction;

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * It gives you a persistent sorted "view" of a configurable subset of your data.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Views
 * 
 * There is also an entire section that details YapDatabaseViewMappings:
 * https://github.com/yapstudios/YapDatabase/wiki/Views#mappings
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
 * This class also assists you in animating changes to your tableView/collectionView.
 * In order to provide the proper animation instructions to your UI,
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
 *     // ...
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
 *         // ... (see https://github.com/yapstudios/YapDatabase/wiki/Views )
 *     }
 *     
 *     for (YapDatabaseViewRowChange *rowChange in rowChanges)
 *     {
 *         // ... (see https://github.com/yapstudios/YapDatabase/wiki/Views )
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
 *      __block id object = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 *         
 *         object = [[transaction ext:@"view"] objectAtIndexPath:indexPath withMappings:mappings];
 *     }];
 * 
 *     // configure and return cell...
 * }
**/

/**
 * The YapDatabaseViewRangePosition struct represents the range window within the full group.
 * @see rangePositionForGroup:
**/
struct YapDatabaseViewRangePosition {
	NSUInteger offsetFromBeginning;
	NSUInteger offsetFromEnd;
	NSUInteger length;
	
};
typedef struct YapDatabaseViewRangePosition YapDatabaseViewRangePosition;

typedef BOOL (^YapDatabaseViewMappingGroupFilter)(NSString *group, YapDatabaseReadTransaction *transaction);
typedef NSComparisonResult (^YapDatabaseViewMappingGroupSort)(NSString *group1, NSString *group2, YapDatabaseReadTransaction *transaction);

@interface YapDatabaseViewMappings : NSObject <NSCopying>

/**
 * Initializes a new mappings object.
 * Use this initializer when the groups, and their order, are known at initialization time.
 *
 * @param allGroups
 *     The ordered array of group names.
 *     From the example above, this would be @[ @"wine", @"liquor", @"beer" ]
 *
 * @param registeredViewName
 *     This is the name of the view, as you registered it with the database system.
**/
+ (instancetype)mappingsWithGroups:(NSArray<NSString *> *)allGroups view:(NSString *)registeredViewName;



/**
 * Initializes a new mappings object with a static list of groups.
 * Use this initializer when the groups, and their order, are known at initialization time.
 * 
 * @param allGroups
 *     The ordered array of group names.
 *     From the example above, this would be @[ @"wine", @"liquor", @"beer" ]
 * 
 * @param registeredViewName
 *     This is the name of the view, as you registered it with the database system.
**/
- (id)initWithGroups:(NSArray<NSString *> *)allGroups
				view:(NSString *)registeredViewName;


/**
 * Initializes a new mappings object that uses a filterBlock and a sortBlock to dynamically construct sections from view.
 * @param filterBlock
 *      Block that takes a string and returns a BOOL.  returning YES will include the group in the sections of the mapping.
 * @param sortBlock
 *      Block used to sort group names for groups that pass the filter.
 * @param registeredViewName
 *      This is the name of the view, as you registered it with the database system.
 *
**/
- (id)initWithGroupFilterBlock:(YapDatabaseViewMappingGroupFilter)filterBlock
                     sortBlock:(YapDatabaseViewMappingGroupSort)sortBlock
                          view:(NSString *)registeredViewName;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The allGroups property returns the groups that were passed in the init method.
 * That is, all groups, whether currently visible or non-visible.
 * 
 * @see visibleGroups
**/
@property (nonatomic, copy, readonly) NSArray<NSString *> *allGroups;

/**
 * The registeredViewName that was passed in the init method.
**/
@property (nonatomic, copy, readonly) NSString *view;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
 * Also note that there's an extremely helpful category: YapDatabaseViewTransaction(Mappings).
 * Methods in this category will be of great help as you take advantage of advanced mappings configurations.
 * For example:
 *
 * id object = [[transaction ext:@"myView"] objectAtIndexPath:indexPath withMappings:mappings];
 *
 * These methods are extensively unit tested to ensure they work properly with all kinds of mappings configurations.
 * Translation: You can use them without thinking, and they'll just work everytime.
 *
 * The mappings object is also used to assist with tableView/collectionView change animations:
 *
 * - YapDatabaseViewConnection getSectionChanges:rowChanges:forNotifications:withMappings:
 * 
 * If all your sections are static, then you won't ever get any section changes.
 * But if you have one or more dynamic sections, then be sure to process the section changes.
 * As the dynamic sections disappear & re-appear, the proper section changes will be emitted.
 *
 * By DEFAULT, all groups/sections are STATIC.
 *
 * You can configure this however you want to meet your needs.
 * This includes per-group configuration, all-at-once, and even overrides.
 * 
 * ORDER MATTERS.
 *
 * If you invoke setIsDynamicSectionForAllGroups, this sets the configuration for every group.
 * Including future groups if using dynamic groups via initWithGroupFilterBlock:sortBlock:view:.
 * 
 * Once the configuration is set for all groups, you can then choose to provide overriden settings for select groups.
 * That is, if you then invoke setIsDynamicSection:forGroup: is will override the "global" setting
 * for this particular group.
**/

- (void)setIsDynamicSection:(BOOL)isDynamic forGroup:(NSString *)group;
- (BOOL)isDynamicSectionForGroup:(NSString *)group;

- (void)setIsDynamicSectionForAllGroups:(BOOL)isDynamic;
- (BOOL)isDynamicSectionForAllGroups;

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
 * with the indexes in the view's group. But don't worry.
 * Just use the methods in "YapDatabaseViewTransaction (Mappings)" to automatically handle it all for you.
 * Or, if you want to be advanced, the various mapping methods in this class.
 * 
 * The rangeOptions you pass in are copied, and YapDatabaseViewMappings keeps a private immutable version of them.
 * So if you make changes to the rangeOptions, you need to invoke this method again to set the changes.
**/

- (void)setRangeOptions:(nullable YapDatabaseViewRangeOptions *)rangeOpts forGroup:(NSString *)group;
- (nullable YapDatabaseViewRangeOptions *)rangeOptionsForGroup:(NSString *)group;

- (void)removeRangeOptionsForGroup:(NSString *)group;

/**
 * There are some times when the drawing of one cell depends somehow on a neighboring cell.
 * For example:
 * 
 * Apple's SMS messaging app draws a timestamp if more than a certain amount of time has elapsed
 * between a message and the previous message. The timestamp is actually drawn at the top of a cell.
 * So cell-B would draw a timestamp at the top of its cell if cell-A represented a message
 * that was sent/received say 3 hours ago.
 * 
 * We refer to this as a "cell drawing dependency". For the example above, the timestamp drawing is dependent
 * upon the cell at offset -1. That is, the drawing of cell at index 5 is dependent upon the cell at index (5-1).
 * 
 * This method allows you to specify if there are cell drawing dependecies.
 * For the example above you could simply do the following:
 * 
 * [mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@""]
 * 
 * This will inject extra YapDatabaseViewChangeUpdate's for cells that may have been affected by
 * other Insert/Delete/Update/Move operations (and thus need to be redrawn).
 * 
 * Continuing the example above, if the item at index 7 is deleted, then changeset processing will automatically emit
 * and update change for the item that was previously at index 8. This is because, as specified by the "cell drawing
 * offset" configuration, the drawing of index 8 was dependent upon the item before it (offset=-1). The item
 * before it has changed, so it gets an update emitted for it automatically.
 *
 * Using this configuration makes it exteremely simple to handle various "cell drawing dependencies".
 * You can just ask for changesets as you would if there weren't any dependencies,
 * perform the boiler-plate updates, and everything just works.
 * 
 * Note that if a YapDatabaseViewChangeUpdate is emitted due to a cell drawing dependeny,
 * AND there were no actual updates for the corresponding item,
 * and you'd like to detect these changes for whatever reason (optimizing, etc),
 * then you can do so by checking to see if the rowChange.changes == YapDatabaseViewChangedDependency.
 * 
 * If you have multiple cell drawing dependencies (e.g. +1 & -1),
 * then you can pass in an NSSet of NSNumbers.
**/

- (void)setCellDrawingDependencyForNeighboringCellWithOffset:(NSInteger)offset forGroup:(NSString *)group;

- (void)setCellDrawingDependencyOffsets:(NSSet<NSNumber *> *)offsets forGroup:(NSString *)group;
- (NSSet<NSNumber *> *)cellDrawingDependencyOffsetsForGroup:(NSString *)group;

/**
 * You can tell mappings to reverse a group/section if you'd like to display it in your tableView/collectionView
 * in the opposite direction in which the items actually exist within the database.
 * 
 * For example:
 * 
 * You have a database view which sorts items by sales rank. The best-selling item is at index 0.
 * Sometimes you use the view to display the top 20 best-selling items.
 * But other times you use the view to display the worst-selling items (perhaps to dump these items in order
 * to make room for new inventory). You want to display the worst-selling item at index 0.
 * And the second worst-selling item at index 1. Etc.
 * This happens to be the opposite sorting order from how the items are in stored in the database.
 * So you simply use the reverse option in mappings to handle the math for you.
 *
 * It's important to understand the relationship between reversing a group and the other mapping options
 * (such as ranges and cell-drawing-dependencies):
 * 
 * Once you reverse a group (setIsReversed:YES forGroup:group) you can visualize the view as reversed in your head,
 * and set all other mappings options as if it was actually reversed.
 * 
 * >>>>> ORDER MATTERS <<<<<
 *
 * To be more precise:
 * 
 * - After reversing a group, you can pass in rangeOptions as if the group were actually reversed in the database.
 *   This makes it easier to configure, as your mental model can match how you configure it.
 * 
 *   rangeOptions = [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewEnd];
 *   [mappings setRangeOptions:rangeOptions forGroup:@"books"];
 *   [mappings setIsReversed:YES forGroup:@"books"];
 * 
 *   is EQUIVALENT to:
 * 
 *   [mappings setIsReversed:YES forGroup:@"books"];
 *   rangeOptions = [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
 *   [mappings setRangeOptions:rangeOptions forGroup:@"books"];
 * 
 * - In terms of cell-drawing-dependencies, its a similar effect.
 * 
 *   [mappings setCellDrawingDependencyForNeighboringCellWithOffset:+1 forGroup:@"books"]; // <-- Positive one
 *   [mappings setIsReversed:YES forGroup:@"books"];
 *
 *   is EQUIVALENT to:
 * 
 *   [mappings setCellDrawingDependencyForNeighboringCellWithOffset:-1 forGroup:@"books"]; // <-- Negative one
 *   [mappings setIsReversed:YES forGroup:@"books"];
 * 
 *
 * In general, if you wish to visualize other configuration options in terms of how they're going to be displayed
 * in your user interface, you should reverse the group BEFORE you make other configuration changes.
 * Alternatively you might visualize it differently. Perhaps you're imaging the database view, applying
 * range options first, and then reversing the final product for dispaly in a tableView.
 * So in this case you should reverse the group AFTER you make other configuration changes.
 *
 * It's simply a matter of how you visualize it.
 * Either order is fine, but one likely makes more sense in your head.
**/

- (void)setIsReversed:(BOOL)isReversed forGroup:(NSString *)group;
- (BOOL)isReversedForGroup:(NSString *)group;

/**
 * This configuration allows you to take multiple groups in a database view,
 * and display them in a single section in your tableView / collectionView.
 * 
 * It's called a "consolidated group".
 * 
 * Further, you can configure a threshold where the mappings will automatically switch between
 * using a "consolidated group" and normal mode.
 *
 * This is useful for those situations where the total number of items in your tableView
 * could be very small or very big. When the count is small, you don't want to use sections.
 * But when the count reaches a certain size, you do want to use sections.
 * For these situations, you can configure the threshold to meet your requirements,
 * and mappings will automatically handle everything for you.
 * Including animating the changes when switching back and forth between consolidated mode and normal mode.
 *
 * The threshold represents the point at which the transition occurs. That is:
 * - if the total number of items is less than the threshold, then consolidated mode will be used.
 * - if the total number of items is equal or greater than the threshold, then normal mode will be used.
 *
 * If the threshold is 0, then auto consolidation is disabled.
 *
 * For example, imagine you're displaying a list of contacts.
 * You might setup a view like this:
 * 
 * view = @{
 *   @"A" : @[ @"Allison Jones" ],
 *   @"B" : @[ @"Billy Bob", @"Brandon Allen" ],
 *   @"R" : @[ @"Ricky Bobby" ]
 * }
 * 
 * The total number of contacts is only 4. So it might look better to display them without sections.
 * However, you're going to want to switch to sections at some point. Perhaps when the total count reaches 10?
 * 
 * It would be nice if there was something to handle this for you.
 * And even better if that something would help you properly animate the tableView
 * when switching between no-sections & sections (and vice versa).
 * This is exactly what the autoConsolidateGroupsThreshold does for you!
 *
 * The default threshold value is 0 (disabled).
**/

- (void)setAutoConsolidateGroupsThreshold:(NSUInteger)threshold withName:(NSString *)consolidatedGroupName;
- (NSUInteger)autoConsolidateGroupsThreshold;
- (NSString *)consolidatedGroupName;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initialization & Updates
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * You have to call this method at least once to initialize the mappings.
 * This method uses the given transaction to fetch and cache the counts for each group.
 * 
 * Mappings are implicitly tied to a databaseConnection's longLivedReadTransaction.
 * That is, when you invoke [databaseConnection beginLongLivedReadTransaction] you are freezing the
 * connection on a particular commit (a snapshot of the database at that point in time).
 * Mappings must always be on the same snapshot as its corresponding databaseConnection.
 * 
 * Eventually, you move the databaseConnection to the latest commit.
 * You do by invoking [databaseConnection beginLongLivedReadTransaction] again.
 * And when you do this you MUST ensure the mappings are also updated to match the databaseConnection's new snapshot.
 *
 * There are 2 ways to do this:
 *
 * - Invoke getSectionChanges:rowChanges:forNotifications:withMappings:.
 *   That method requires the 'before' & 'after' snapshot of the mappings in order to calculate the proper changeset.
 *   And in order to get this, it automatically invokes this method.
 *
 * - Invoke this method again.
 *   And do NOT invoke getSectionChanges:rowChanges:forNotifications:withMappings:.
 *   You might take this route if the viewController isn't visible,
 *   and you're simply planning on doing a [tableView reloadData].
 * 
 * Please also see the example code above.
**/
- (void)updateWithTransaction:(YapDatabaseReadTransaction *)transaction;

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
 * @see YapDatabaseConnection snapshot
**/
@property (nonatomic, readonly) uint64_t snapshotOfLastUpdate;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the actual number of visible sections.
 *
 * This number may be less than the original count of groups passed in the init method.
 * That is, if dynamic sections are enabled for one or more groups, and some of these groups have zero items,
 * then those groups will be removed from the visible list of groups. And thus the section count may be less.
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
 * The visibleGroups property returns the current sections setup.
 * That is, it only contains the visible groups that are being represented as sections in the view.
 *
 * If all sections are static, then visibleGroups will always be the same as allGroups.
 * However, if one or more sections are dynamic, then the visible groups may be a subset of allGroups.
 *
 * Dynamic groups/sections automatically "disappear" if/when they become empty.
**/
- (NSArray *)visibleGroups;

/**
 * Returns YES if there are zero items in all sections/groups.
**/
- (BOOL)isEmpty;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mapping: UI -> YapDatabaseView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Maps from a section (in the UI) to a group (in the View).
 *
 * Returns the group for the given section.
 * This method properly takes into account dynamic groups.
 *
 * If the section is out-of-bounds, returns nil.
**/
- (NSString *)groupForSection:(NSUInteger)section;

/**
 * Maps from an indexPath (in the UI) to a group & index (within the View).
 *
 * When your UI doesn't exactly match up with the View in the database, this method does all the math for you.
 *
 * For example, if using rangeOptions, the rows in your tableView/collectionView may not
 * directly match the index in the corresponding view & group (in the database).
 * 
 * For example, say a view in the database has a group named "elders" and contains 100 items.
 * A fixed range is used to display only the last 20 items in the "elders" group (the 20 oldest elders).
 * Thus row zero in the tableView is actually index 80 in the "elders" group.
 *
 * So you pass in an indexPath or row & section from the UI perspective,
 * and it spits out the corresponding index within the database view's group.
 * 
 * Code sample:
 * 
 * - (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
 * {
 *     NSString *group = nil;
 *     NSUInteger groupIndex = 0;
 *
 *     [mappings getGroup:&group index:&groupIndex forIndexPath:indexPath];
 *
 *     __block Elder *elder = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *
 *         elder = [[transaction extension:@"elders"] objectAtIndex:groupIndex inGroup:group];
 *     }];
 *     
 *     // configure and return cell...
 * }
**/
- (BOOL)getGroup:(NSString * _Nonnull * _Nullable)groupPtr index:(nullable NSUInteger *)indexPtr forIndexPath:(NSIndexPath *)indexPath;

/**
 * Maps from an indexPath (in the UI) to a group & index (within the View).
 *
 * When your UI doesn't exactly match up with the View in the database, this method does all the math for you.
 *
 * For example, if using rangeOptions, the rows in your tableView/collectionView may not
 * directly match the index in the corresponding view & group (in the database).
 * 
 * For example, say a view in the database has a group named "elders" and contains 100 items.
 * A fixed range is used to display only the last 20 items in the "elders" group (the 20 oldest elders).
 * Thus row zero in the tableView is actually index 80 in the "elders" group.
 *
 * So you pass in an indexPath or row & section from the UI perspective,
 * and it spits out the corresponding index within the database view's group.
 * 
 * Code sample:
 * 
 * - (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
 * {
 *     NSString *group = nil;
 *     NSUInteger groupIndex = 0;
 *
 *     [mappings getGroup:&group index:&groupIndex forIndexPath:indexPath];
 *
 *     __block Elder *elder = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *
 *         elder = [[transaction extension:@"elders"] objectAtIndex:groupIndex inGroup:group];
 *     }];
 *     
 *     // configure and return cell...
 * }
**/
- (BOOL)getGroup:(NSString * _Nonnull * _Nullable)groupPtr
           index:(nullable NSUInteger *)indexPtr
          forRow:(NSUInteger)row
       inSection:(NSUInteger)section;

/**
 * Maps from a row & section (in the UI) to an index (within the View).
 * 
 * This method is shorthand for getGroup:index:forIndexPath: when you already know the group.
 * @see getGroup:index:forIndexPath:
 * 
 * Returns NSNotFound if the given row & section are invalid.
**/
- (NSUInteger)indexForRow:(NSUInteger)row inSection:(NSUInteger)section;

/**
 * Maps from a row & section (in the UI) to an index (within the View).
 * 
 * This method is shorthand for getGroup:index:forIndexPath: when you already know the group.
 * @see getGroup:index:forIndexPath:
 * 
 * Returns NSNotFound if the given row & group are invalid.
**/
- (NSUInteger)indexForRow:(NSUInteger)row inGroup:(NSString *)group;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mapping: YapDatabaseView -> UI
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Maps from a group (in the View) to the corresponding section (in the UI).
 *
 * Returns the visible section number for the visible group.
 * Returns NSNotFound if the group is NOT visible (or invalid).
**/
- (NSUInteger)sectionForGroup:(NSString *)group;

/**
 * Maps from an index & group (in the View) to the corresponding row & section (in the UI).
 * 
 * Returns YES if the proper row & section were found.
 * Returns NO if the given index is NOT visible (or out-of-bounds).
 * Returns NO if the given group is NOT visible (or invalid).
**/
- (BOOL)getRow:(nullable NSUInteger *)rowPtr
       section:(nullable NSUInteger *)sectionPtr
      forIndex:(NSUInteger)index
       inGroup:(NSString *)group;

/**
 * Maps from an index & group (in the View) to the corresponding indexPath (in the UI).
 * 
 * Returns the indexPath with the proper section and row.
 * Returns nil if the given index & group is NOT visible (or out-of-bounds).
**/
- (nullable NSIndexPath *)indexPathForIndex:(NSUInteger)index inGroup:(NSString *)group;

/**
 * Maps from an index & group (in the View) to the corresponding row (in the UI).
 * 
 * This method is shorthand for getRow:section:forIndex:inGroup: when you already know the section.
 * @see getRow:section:forIndex:inGroup:
 * 
 * Returns NSNotFound if the given index & group is NOT visible (or out-of-bounds).
**/
- (NSUInteger)rowForIndex:(NSUInteger)index inGroup:(NSString *)group;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters + Consolidation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Whether or not the groups have been automatically consolidated due to the configured autoConsolidateGroupsThreshold.
**/
- (BOOL)isUsingConsolidatedGroup;

/**
 * Returns the total number of items by summing up the totals across all groups.
**/
- (NSUInteger)numberOfItemsInAllGroups;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters + Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapDatabaseViewRangePosition struct represents the range window within the full group.
 * For example:
 *
 * You have a section in your tableView which represents a group that contains 100 items.
 * However, you've setup rangeOptions to only display the first 20 items:
 *
 * YapDatabaseViewRangeOptions *rangeOptions =
 *     [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
 * [mappings setRangeOptions:rangeOptions forGroup:@"sales"];
 *
 * The corresponding rangePosition would be: (YapDatabaseViewRangePosition){
 *     .offsetFromBeginning = 0,
 *     .offsetFromEnd = 80,
 *     .length = 20
 * }
**/
- (YapDatabaseViewRangePosition)rangePositionForGroup:(NSString *)group;

/**
 * This is a helper method to assist in maintaining the selection while updating the tableView/collectionView.
 * In general the idea is this:
 * - yapDatabaseModified is invoked on the main thread
 * - at the beginning of the method, you grab some information about the current selection
 * - you update the database connection, and then start the animation for the changes to the table
 * - you reselect whatever was previously selected
 * - if that's not possible (row was deleted) then you select the closest row to the previous selection
 * 
 * The last step isn't always what you want to do. Maybe you don't want to select anything at that point.
 * But if you do, then this method can simplify the task for you.
 * 
 * For example:
 * 
 * - (void)yapDatabaseModified:(NSNotification *)notification {
 * 
 *     // Grab info about current selection
 *     
 *     NSString *selectedGroup = nil;
 *     NSUInteger selectedRow = 0;
 *     __block NSString *selectedWidgetId = nil;
 *
 *     NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
 *     if (selectedIndexPath) {
 *         selectedGroup = [mappings groupForSection:selectedIndexPath.section];
 *         selectedRow = selectedIndexPath.row;
 *         
 *         [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *             selectedWidgetId = [[transaction ext:@"widgets"] keyAtIndex:selectedRow inGroup:selectedGroup];
 *         }];
 *     }
 *     
 *     // Update the database connection (move it to the latest commit)
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
 *     if ([sectionChanges count] == 0 & [rowChanges count] == 0)
 *     {
 *         // Nothing has changed that affects our tableView
 *         return;
 *     }
 *
 *     // Update the table (animating the changes)
 *
 *     [self.tableView beginUpdates];
 *
 *     for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
 *     {
 *         // ... (see https://github.com/yapstudios/YapDatabase/wiki/Views )
 *     }
 *
 *     for (YapDatabaseViewRowChange *rowChange in rowChanges)
 *     {
 *         // ... (see https://github.com/yapstudios/YapDatabase/wiki/Views )
 *     }
 *
 *     [self.tableView endUpdates];
 *     
 *     // Try to reselect whatever was selected before
 * 
 *     __block NSIndexPath *indexPath = nil;
 *
 *     if (selectedIndexPath) {
 *         [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *             indexPath = [[transaction ext:@"widgets"] indexPathForKey:selectedWidgetId
 *                                                          withMappings:mappings];
 *         }];
 *     }
 * 
 *     // Otherwise select the nearest row to whatever was selected before
 * 
 *     if (!indexPath && selectedGroup) {
 *         indexPath = [mappings nearestIndexPathForRow:selectedRow inGroup:selectedGroup];
 *     }
 *     
 *     if (indexPath) {
 *         [self.tableView selectRowAtIndexPath:indexPath
 *                                     animated:NO
 *                               scrollPosition:UITableViewScrollPositionMiddle];
 *     }
 * }
**/
- (nullable NSIndexPath *)nearestIndexPathForRow:(NSUInteger)row inGroup:(NSString *)group;

@end

NS_ASSUME_NONNULL_END
