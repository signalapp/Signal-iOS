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
 * for sale in the liquor department then it can automatically move beer to section 1.
 * 
 * But the primary purpose of this class has to do with assisting in animating changes to your view.
 * In order to provide the proper animation instructions to your tableView or collectionView,
 * the database layer needs to know a little about how you're setting things up.
 * 
 * @see YapDatabaseViewConnection changesForNotifications:withGroupToSectionMappings:
 * @see YapCollectionsDatabaseViewConnection changesForNotifications:withGroupToSectionMappings:
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
 * What happens if a group/section has zero items?
 * Do you want the section to disappear from the view?
 * Or do you want the section to remain visible?
 * 
 * If allowsEmptySections is NO, then sections that have zero items automatically get removed.
 *
 * The default value is NO.
**/
@property (nonatomic, assign, readwrite) BOOL allowsEmptySections;

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
//- (void)setMinKey:(id)key forGroup:(NSString *)group;
//- (void)setMaxKey:(id)key forGroup:(NSString *)group;
//- (void)setHardRange:(NSRange)range forGroup:(NSString *)group;


#pragma mark Update

/**
 * You have to call this method to initialize the mappings.
 * This method uses the transaction fetch and cache the counts for the groups.
 * 
 * This class is most often used with the method changesForNotifications:withMappings:,
 * and that method automatically invokes this method after it has used the mappings to
 * calculate the proper sections & indexes for the animations.
 * 
 * You generally only have to invoke this method again (after the initialization),
 * if you make changes to the configuration using the various properties.
**/
- (void)updateWithTransaction:(YapAbstractDatabaseTransaction *)transaction;


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
