/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseCloudCoreOptions.h"
#import "YapDatabaseCloudCoreConnection.h"
#import "YapDatabaseCloudCoreTransaction.h"

#import "YapDatabaseCloudCoreOperation.h"

#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseCloudCoreGraph.h"

/**
 * Serialization/Deserialization for operation objects.
 *
 * The default version uses NSCoding.
 * However, an alternative may be substitued if desired.
**/
typedef NSData* (^YDBCloudCoreOperationSerializer)(YapDatabaseCloudCoreOperation *operation);
typedef YapDatabaseCloudCoreOperation* (^YDBCloudCoreOperationDeserializer)(NSData *operationBlob);


extern NSString *const YapDatabaseCloudCoreDefaultPipelineName; // = @"default";


@interface YapDatabaseCloudCore : YapDatabaseExtension

- (instancetype)initWithVersionTag:(NSString *)versionTag
                           options:(YapDatabaseCloudCoreOptions *)options;

@property (nonatomic, copy, readonly) NSString *versionTag;

@property (nonatomic, copy, readonly) YapDatabaseCloudCoreOptions *options;

#pragma mark General Configuration

+ (YDBCloudCoreOperationSerializer)defaultOperationSerializer;
+ (YDBCloudCoreOperationDeserializer)defaultOperationDeserializer;

- (BOOL)setOperationSerializer:(YDBCloudCoreOperationSerializer)serializer
                  deserializer:(YDBCloudCoreOperationDeserializer)deserializer;

@property (nonatomic, strong, readonly) YDBCloudCoreOperationSerializer operationSerializer;
@property (nonatomic, strong, readonly) YDBCloudCoreOperationDeserializer operationDeserializer;


#pragma mark Pipelines

- (YapDatabaseCloudCorePipeline *)defaultPipeline;

/**
 * Returns the registered pipeline with the given name.
 * If no pipeline is registered under the given name, returns nil.
**/
- (YapDatabaseCloudCorePipeline *)pipelineWithName:(NSString *)name;

/**
 * Attempts to register the given pipeline.
 * 
 * All pipelines MUST be registered BEFORE the extension itself is registered with the database.
 * 
 * The given pipeline may be in a suspended or non-suspended state.
 * Pipelines are fully capable of queueing work until they are resumed, or until network access is restored.
 *
 * During registration, the given pipeline will automatically have its suspendCount incremented in accordance
 * with the suspendCount of this instance. That is, YapDatabaseCloudCore has suspend/resume methods that automatically
 * invoke the corresponding suspend/resume methods of every registered pipeline. Thus if you have invoked
 * [YapDatabaseCloudCore suspend] twice (and thus it currently has a suspendCount of 2), then during registration
 * of the pipeline, the pipeline's suspendCount will be incremented by 2. This means you can separate your
 * management of suspending/resuming the extension with setting up & installing your pipeline(s). And you need not
 * worry about suspendCount mismanagement concerning this particlar situation.
 *
 * @return YES if the registration was successful, NO otherwise.
**/
- (BOOL)registerPipeline:(YapDatabaseCloudCorePipeline *)pipeline;

/**
 * Returns all the registered pipelines.
**/
- (NSArray<YapDatabaseCloudCorePipeline *> *)registeredPipelines;

/**
 * Returns all the registered pipeline names.
**/
- (NSArray<NSString *> *)registeredPipelineNames;


#pragma mark Suspend & Resume

/**
 * Each pipeline has its own suspendCount, and suspend/resume methods.
 * The methods of this class allow you to invoke the suspend/resume method of every registered pipeline.
**/

/**
 * Returns whether or not the suspendCount is non-zero.
 *
 * Remember that each pipeline has its own suspendCount, and suspend/resume methods.
 * So even if the extension isn't suspended as a whole, an individual pipeline may be.
**/
@property (atomic, readonly) BOOL isSuspended;

/**
 * Returns whether or not the suspendCount is non-zero.
 *
 * Remember that each pipeline has its own suspendCount, and suspend/resume methods.
 * So even if the extension isn't suspended as a whole, an individual pipeline may be.
**/
@property (atomic, readonly) NSUInteger suspendCount;

/**
 * Invokes the suspend method of every registerd pipeline, and also increments the local suspendCount.
**/
- (NSUInteger)suspend;
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement;

/**
 * Invokes the resume method of every registerd pipeline, and also decrements the local suspendCount.
**/
- (NSUInteger)resume;

@end
