#import <Foundation/Foundation.h>
#import "YapDatabaseSecondaryIndexSetup.h"


@interface YapDatabaseSecondaryIndexSetup ()

/**
 * This method compares its setup to a current table structure.
 * 
 * @param columns
 *   
 *   Dictionary of column names and affinity.
 * 
 * @see YapDatabase columnNamesAndAffinityForTable:using:
**/
- (BOOL)matchesExistingColumnNamesAndAffinity:(NSDictionary *)columns;

@end
