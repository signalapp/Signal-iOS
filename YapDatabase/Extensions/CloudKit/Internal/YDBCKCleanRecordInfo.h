#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

/**
 * This class represents information about an unmodified row & corresponding CKRecord.
 *
 * The YapDatabaseCloudKitConnection.cache dictionary stores objects of this type.
 * Specifically:
 *
 * cleanRecordInfo.key = NSNumber (rowid)
 * cleanRecordInfo.value = YDBCKCleanRecordInfo
**/
@interface YDBCKCleanRecordInfo : NSObject

@property (nonatomic, copy, readwrite) NSString *databaseIdentifier;
@property (nonatomic, strong, readwrite) CKRecord *record;

@end
