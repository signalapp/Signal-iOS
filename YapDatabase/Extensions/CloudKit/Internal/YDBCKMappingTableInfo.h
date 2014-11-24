#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@class YDBCKDirtyMappingTableInfo;

@protocol YDBCKMappingTableInfo <NSObject>
@property (nonatomic, strong, readonly) NSString *current_recordTable_hash;
@end

/**
 * This class represents information about an unmodified row in the mapping table.
 * 
 * YapDatabaseCloudKitConnection.cleanMappingTableInfo stores instances of this type:
 * 
 * cleanMappingTableInfo.key = rowid (NSNumber)
 * cleanMappingTableInfo.value = YDBCKCleanMappingTableInfo
**/
@interface YDBCKCleanMappingTableInfo : NSObject <YDBCKMappingTableInfo>

- (instancetype)initWithRecordTableHash:(NSString *)hash;

@property (nonatomic, strong, readonly) NSString *recordTable_hash;

- (YDBCKDirtyMappingTableInfo *)dirtyCopy;

@end

#pragma mark -

/**
 * This class represents information about a modified row in the mapping table.
 * 
 * YapDatabaseCloudKitConnection.dirtyMappingTableInfo stores instances of this type:
 * 
 * dirtyMappingTableInfo.key = rowid (NSNumber)
 * dirtyMappingTableInfo.value = YDBCKDirtyMappingTableInfo
**/
@interface YDBCKDirtyMappingTableInfo : NSObject <YDBCKMappingTableInfo>

- (instancetype)initWithRecordTableHash:(NSString *)hash;

@property (nonatomic, strong, readonly)  NSString *clean_recordTable_hash;
@property (nonatomic, strong, readwrite) NSString *dirty_recordTable_hash;

- (YDBCKCleanMappingTableInfo *)cleanCopy;

@end