#import <Foundation/Foundation.h>
#import "sqlite3.h"

@class YapEnumerateStatement;

/**
 * This class is used for enumerate statements in order to fix the
 * "enumerate within enumerate" bug.
 * 
 * For example:
 * 
 * [transaction enumerateRowsInCollection:@"teams"
 *                             usingBlock:^(NSString *key, id object, id metadata, BOOL *stop)
 * {
 *     Team *team = (Team *)object;
 * 
 *     [transaction enumerateRowsInCollection:team.name
 *                             usingBlock:^(NSString *key, id object, id metadata, BOOL *stop)
 *     {
 *         // This "child" enumerate would mess up the "parent" enumerate 
 *         // IF they were sharing the same sqlite3_stmt instance.
 *     }];
 * }];
**/
@interface YapEnumerateStatementFactory : NSObject

- (instancetype)initWithDb:(sqlite3 *)db statement:(NSString *)stmtString;

- (YapEnumerateStatement *)newStatement:(int *)statusPtr;

@end


@interface YapEnumerateStatement : NSObject

@property (nonatomic, assign, readonly) sqlite3_stmt *statement;

@end
