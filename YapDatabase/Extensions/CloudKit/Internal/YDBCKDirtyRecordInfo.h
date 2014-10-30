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

@property (nonatomic, assign, readwrite) BOOL skipUploadRecord;
@property (nonatomic, assign, readwrite) BOOL skipUploadDeletion;
@property (nonatomic, assign, readwrite) BOOL remoteDeletion;
@property (nonatomic, assign, readwrite) BOOL remoteMerge;

/**
 * Returns YES if there wasn't a record previously associated with this item.
 * In other words, if clean_recordID is nil.
**/
- (BOOL)wasInserted;

/**
 * Returns YES if the recordID/databaseIdentifier has changed.
 * In other words, it compares clean_recordID vs dirty_recordID,
 * and clean_databaseIdentifier vs dirty_databaseIdentifier.
**/
- (BOOL)databaseIdentifierOrRecordIDChanged;

@end
