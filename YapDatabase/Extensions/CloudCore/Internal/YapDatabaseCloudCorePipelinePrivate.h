/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseCloudCoreGraph.h"


@interface YapDatabaseCloudCorePipeline ()

@property (nonatomic, assign, readwrite) int64_t rowid;

- (NSArray<NSArray<YapDatabaseCloudCoreOperation *> *> *)graphOperations;

- (void)getGraphUUID:(NSUUID **)outGraphUUID
       prevGraphUUID:(NSUUID **)outPrevGraphUUID
         forGraphIdx:(NSUInteger)graphIdx;

- (BOOL)_getStatus:(YDBCloudCoreOperationStatus *)statusPtr
          isOnHold:(BOOL *)isOnHoldPtr
  forOperationUUID:(NSUUID *)opUUID;

- (void)restoreGraphs:(NSArray *)graphs;

- (void)processAddedGraph:(YapDatabaseCloudCoreGraph *)graph
		 insertedOperations:(NSDictionary<NSNumber *, NSArray<YapDatabaseCloudCoreOperation *> *> *)insertedOperations
       modifiedOperations:(NSDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *)modifiedOperations;

- (YapDatabaseCloudCoreGraph *)lastGraph;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreGraph ()

- (instancetype)initWithUUID:(NSUUID *)uuid operations:(NSArray<YapDatabaseCloudCoreOperation *> *)operations;

@property (nonatomic, strong, readonly) NSUUID *uuid;
@property (nonatomic, strong, readonly) NSArray<YapDatabaseCloudCoreOperation *> *operations;

@property (nonatomic, unsafe_unretained, readwrite) YapDatabaseCloudCorePipeline *pipeline;

- (void)insertOperations:(NSArray<YapDatabaseCloudCoreOperation *> *)insertedOperations
        modifyOperations:(NSDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *)modifiedOperations
                modified:(NSMutableArray<YapDatabaseCloudCoreOperation *> *)matchedModifiedOperations;

- (NSArray *)removeCompletedAndSkippedOperations;

- (YapDatabaseCloudCoreOperation *)dequeueNextOperation;

@end
