#import <Foundation/Foundation.h>

typedef enum {
	YapDatabaseViewOperationMove,
	YapDatabaseViewOperationInsert,
	YapDatabaseViewOperationDelete,
	
} YapDatabaseViewOperationType;


@interface YapDatabaseViewOperation : NSObject {
@public
	
	id key;                // consider immutable
	NSString *group;       // consider immutable
	
	NSUInteger opOriginal; // consider immutable
	NSUInteger opFinal;    // consider immutable
	
	YapDatabaseViewOperationType type; // mutable during consolidation
	
	NSUInteger original; // mutable during post-processing
	NSUInteger final;    // mutable during post-processing
}

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;
+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;

+ (void)postProcessAndConsolidateOperations:(NSMutableArray *)operations;

@end
