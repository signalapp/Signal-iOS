/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

#import "YapDatabaseCloudCoreOperation.h"


/**
 * A graph contains all the cloud operations that were generated in a single commit (for a
 * specific pipeline). Within the graph are the various operations with their different dependencies & priorities.
 * 
 * The graph is in charge of managing the execution order of the operations
 * in accordance with the set dependencies & priorities.
**/
@interface YapDatabaseCloudCoreGraph : NSObject

/**
 * A graph's operations are managed by the pipeline.
 * Use the methods in YapDatabaseCloudCorePipeline to enumerate operations in a graph.
**/

@end
