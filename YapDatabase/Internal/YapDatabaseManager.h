#import <Foundation/Foundation.h>

/**
 * There should only be one YapDatabase instance per file.
 *
 * The architecture design is to create a single parent database instance,
 * and then spawn connections to the database as needed from the parent.
 * 
 * The architecture is built around this restriction, and is dependent upon it for proper operation.
 * This class simply helps maintain this requirement.
**/
@interface YapDatabaseManager : NSObject

+ (BOOL)registerDatabaseForPath:(NSString *)path;
+ (void)deregisterDatabaseForPath:(NSString *)path;

@end
