#import <Foundation/Foundation.h>

typedef enum {
	YapDatabaseViewOperationMove,
	YapDatabaseViewOperationInsert,
	YapDatabaseViewOperationDelete,
	
} YapDatabaseViewOperationType;


@interface YapDatabaseViewOperation : NSObject

+ (YapDatabaseViewOperation *)insertKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;
+ (YapDatabaseViewOperation *)deleteKey:(id)key inGroup:(NSString *)group atIndex:(NSUInteger)index;

+ (void)postProcessAndConsolidateOperations:(NSMutableArray *)operations;

@property (nonatomic, readonly) id key;

@property (nonatomic, readonly) YapDatabaseViewOperationType type;

@property (nonatomic, readonly) NSUInteger originalIndex;
@property (nonatomic, readonly) NSUInteger finalIndex;

@end
