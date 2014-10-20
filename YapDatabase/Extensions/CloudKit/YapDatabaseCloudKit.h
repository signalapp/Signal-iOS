#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitOptions.h"
#import "YapDatabaseCloudKitConnection.h"
#import "YapDatabaseCloudKitTransaction.h"


@interface YapDatabaseCloudKit : YapDatabaseExtension

/**
 * 
**/
- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                           versionTag:(NSString *)versionTag;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                           versionTag:(NSString *)versionTag
                              options:(YapDatabaseCloudKitOptions *)options;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                        databaseBlock:(YapDatabaseCloudKitDatabaseBlock)databaseBlock
                           versionTag:(NSString *)versionTag
                              options:(YapDatabaseCloudKitOptions *)options;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitRecordBlock recordBlock;
@property (nonatomic, assign, readonly) YapDatabaseCloudKitBlockType recordBlockType;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitMergeBlock mergeBlock;
@property (nonatomic, strong, readonly) YapDatabaseCloudKitConflictBlock conflictBlock;

@property (nonatomic, copy, readonly) NSString *versionTag;

@property (nonatomic, copy, readonly) YapDatabaseCloudKitOptions *options;

/**
 * 
**/
@property (atomic, assign, readwrite, getter=isPaused) BOOL paused;

@end
