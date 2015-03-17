#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@class YDBCKDirtyRecordTableInfo;

@protocol YDBCKRecordTableInfo <NSObject>

@property (nonatomic, readonly) NSString * databaseIdentifier;
@property (nonatomic, readonly) CKRecord * current_record;
@property (nonatomic, readonly) int64_t    current_ownerCount;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This class represents information about an unmodified row in the record table.
 *
 * YapDatabaseCloudKitConnection.cleanRecordTableInfo stores objects of this type:
 *
 * cleanRecordTableInfo.key = Hash(CKRecordID + databaseIdentifier)
 * cleanRecordTableInfo.value = YDBCKCleanRecordTableInfo
**/
@interface YDBCKCleanRecordTableInfo : NSObject <YDBCKRecordTableInfo>

- (instancetype)initWithDatabaseIdentifier:(NSString *)databaseIdentifier
                                ownerCount:(int64_t)ownerCount
                                    record:(CKRecord *)record;

@property (nonatomic, readonly) NSString * databaseIdentifier;
@property (nonatomic, readonly) int64_t    ownerCount;
@property (nonatomic, readonly) CKRecord * record;

- (YDBCKDirtyRecordTableInfo *)dirtyCopy;

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)record;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This class represents information about a modified row in the record table.
 *
 * YapDatabaseCloudKitConnection.dirtyRecordTableInfo dictionary stores objects of this type:
 *
 * dirtyRecordTableInfo.key = Hash(CKRecordID + databaseIdentifier)
 * dirtyRecordTableInfo.value = YDBCKDirtyRecordTableInfo
**/
@interface YDBCKDirtyRecordTableInfo : NSObject <YDBCKRecordTableInfo>

- (instancetype)initWithDatabaseIdentifier:(NSString *)databaseIdentifier
                                  recordID:(CKRecordID *)recordID
                                ownerCount:(int64_t)clean_ownerCount;

@property (nonatomic, readonly) NSString *databaseIdentifier;
@property (nonatomic, readonly) CKRecordID *recordID;

@property (nonatomic, readonly) int64_t clean_ownerCount;            // represents what's on disk

@property (nonatomic, assign, readonly)  int64_t   dirty_ownerCount; // represents new value (this transaction)
@property (nonatomic, strong, readwrite) CKRecord *dirty_record;     // represents new value (this transaction)

@property (nonatomic, assign, readwrite) BOOL skipUploadRecord;
@property (nonatomic, assign, readwrite) BOOL skipUploadDeletion;
@property (nonatomic, assign, readwrite) BOOL remoteDeletion;
@property (nonatomic, assign, readwrite) BOOL remoteMerge;

@property (nonatomic, copy, readonly) NSDictionary *originalValues;
- (void)mergeOriginalValues:(NSDictionary *)inOriginalValues;

- (void)incrementOwnerCount;
- (void)decrementOwnerCount;

- (BOOL)ownerCountChanged;
- (BOOL)hasNilRecordOrZeroOwnerCount;

- (YDBCKCleanRecordTableInfo *)cleanCopyWithSanitizedRecord:(CKRecord *)record;

@end
