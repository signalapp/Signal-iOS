#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseExtensionConnection.h"
#import "YapDatabaseViewOperation.h"

@class YapDatabaseView;


@interface YapDatabaseViewConnection : YapAbstractDatabaseExtensionConnection

@property (nonatomic, strong, readonly) YapDatabaseView *view;

/**
 * Familiar with NSFetchedResultsController?
 * Want an exact list of changes that happend to the view during any number of readwrite transactions?
 *
 * You're in luck!
 * This is what this method does.
 *
 * Here's how it works:
 *
**/
- (NSArray *)operationsForNotifications:(NSArray *)notifications withGroupToSectionMappings:(NSDictionary *)mappings;

@end
