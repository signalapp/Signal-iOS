#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

/**
 * This class represents information about a modified row & corresponding CKRecord.
 * 
 * The YapDatabaseCloudKitConnection.dirtyRecordInfo dictionary stores objects of this type.
 * Specifically:
 * 
 * dirtyRecordInfo.key = NSNumber (rowid)
 * dirtyRecordInfo.value = YDBCKDirtyRecordInfo
**/
@interface YDBCKDirtyRecordInfo : NSObject

@property (nonatomic, strong, readwrite) CKRecordID *clean_recordID;        // represents what's on disk
@property (nonatomic, copy, readwrite) NSString *clean_databaseIdentifier;  // represents what's on disk

@property (nonatomic, strong, readwrite) CKRecord *dirty_record;            // represents new value (this transaction)
@property (nonatomic, copy, readwrite) NSString *dirty_databaseIdentifier;  // represents new value (this transaction)

@property (nonatomic, assign, readwrite) BOOL detached;

- (BOOL)wasInserted;

- (BOOL)databaseIdentifierOrRecordIDChanged;

@end
