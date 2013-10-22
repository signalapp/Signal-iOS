#import <Foundation/Foundation.h>
#import "sqlite3.h"

/**
 * Simple wrapper class to facilitate storing sqlite3_stmt items as objects (primarily in YapCache).
**/
@interface YapDatabaseStatement : NSObject

- (id)initWithStatement:(sqlite3_stmt *)stmt;

@property (nonatomic, assign, readonly) sqlite3_stmt *stmt;

@end
