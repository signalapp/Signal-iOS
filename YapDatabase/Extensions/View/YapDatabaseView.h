#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtension.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to check out the wiki
 * https://github.com/yaptv/YapDatabase/wiki
 * 
 * YapDatabaseView is an extension designed to work with YapDatabase.
 * 
 * What is an extension?
 * An extension is a special type of class that can optionally be plugged into YapDatabase.
 * To use an extension you instantiate one and then "register" it with the database.
 * An extension implements a number of "hooks" that tell the extension about changes being made to the database.
 * Basically when you call methods like [transaction setObject:forKey:],
 * YapDatabase automatically forwards the changes to all registered extensions.
 * 
 * YapDatabaseView provides the ability to create a "view" of your data.
 * That is, imagine you want to display your data in a table.
 *
 * - Do you want to display all your data, or just a subset of it?
 * - Do you want to group it into sections?
 * - How do you want to sort the objects?
 * 
 * In sqlite terms, this translates into:
 * - WHERE ...     (filter)
 * - GROUP BY ...  (group)
 * - ORDER BY ...  (sort)
 * 
 * And this is essentially what a view does.
 * It allows you to specify the terms of the view by answering the 3 questions above.
 * Furthermore, a view is persistent. So when you alter the table, the view is automatically updated as well.
 * 
 * Let's start from the beginning.
 * When you create an instance of a view, you specify 2 blocks:
 *
 * - The first block is called the grouping block, and it handles both filtering and grouping.
 *   When you add or update rows in the databse the grouping block is invoked.
 *   Your grouping block can inspect the row and determine if it should be a part of the view.
 *   If not, your grouping block simply returns 'nil' and the object is excluded from the view (removing it if needed).
 *   Otherwise your grouping block returns a group, which can be any string you want.
 *   Once the view knows what group the row belongs to,
 *   it then needs to determine the index/position of the row within the group.
 *
 * - The second block is called the sorting block, and it handles sorting.
 *   After invoking the grouping block to determine what group a database row belongs to (if any),
 *   the view then needs to determine what index within that group the row should be.
 *   In order to do this, it needs to compare the new/updated row with existing rows in the same view group.
 *   This is what the sorting block is used for.
 *   So the sorting block will be invoked automatically during this process until the view has come to a conclusion.
 *
 * The steps to setup and use YapDatabaseView:
 *
 * 1. Create an instance of it (configured however you like):
 *
 *    YapDatabaseView *myView = [[YapDatabaseView alloc] initWith...];
 *
 * 2. Then you register the view with the databse:
 *
 *    [myDatabase registerExtension:myView withName:@"view"];
 *
 * 3. Access the view within a transaction (just like you access the databse):
 * 
 *    [myDatabaseConnection readWithTransaction:^(YapDatabaseReadTransaction *transaction){
 *        
 *        [[transaction extension:@"view"] objectAtIndex:0 inGroup:@"songs"];
 *    }];
 *
 * @see [YapAbstractDatabase registerExtension:withName:]
**/

typedef id YapDatabaseViewGroupingBlock; // One of the YapDatabaseViewGroupingX types below.

typedef NSString* (^YapDatabaseViewGroupingWithObjectBlock)(NSString *key, id object);
typedef NSString* (^YapDatabaseViewGroupingWithMetadataBlock)(NSString *key, id metadata);
typedef NSString* (^YapDatabaseViewGroupingWithObjectAndMetadataBlock)(NSString *key, id object, id metadata);

typedef id YapDatabaseViewSortingBlock; // One of the YapDatabaseViewSortingX types below.

typedef NSComparisonResult (^YapDatabaseViewSortingWithObjectBlock) \
                 (NSString *group, NSString *key1, id object1, NSString *key2, id object2);
typedef NSComparisonResult (^YapDatabaseViewSortingWithMetadataBlock) \
                 (NSString *group, NSString *key1, id metadata, NSString *key2, id metadata2);
typedef NSComparisonResult (^YapDatabaseViewSortingWithObjectAndMetadataBlock) \
                 (NSString *group, NSString *key1, id object1, id metadata1, NSString *key2, id object2, id metadata2);


typedef enum {
	YapDatabaseViewBlockTypeWithObject,
	YapDatabaseViewBlockTypeWithMetadata,
	YapDatabaseViewBlockTypeWithObjectAndMetadata
} YapDatabaseViewBlockType;



@interface YapDatabaseView : YapAbstractDatabaseExtension

/* Inherited from YapAbstractDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

/**
 * To create a view you 
**/
- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)groupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)groupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)sortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)sortingBlockType;

@property (nonatomic, strong, readonly) YapDatabaseViewGroupingBlock groupingBlock;
@property (nonatomic, strong, readonly) YapDatabaseViewSortingBlock sortingBlock;

@property (nonatomic, assign, readonly) YapDatabaseViewBlockType groupingBlockType;
@property (nonatomic, assign, readonly) YapDatabaseViewBlockType sortingBlockType;

@end
