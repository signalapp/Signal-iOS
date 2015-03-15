#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>


@interface CKRecord (YapDatabaseCloudKit)

/**
 * Returns a "sanitized" copy of the given record.
 * That is, a copy that ONLY includes the "system fields" of the record.
 * It will NOT contain any key/value pairs from the original record.
**/
- (id)sanitizedCopy;

/**
 * Calling [ckRecord copy] is COMPLETELY BROKEN.
 * This is a MAJOR BUG in Apple's CloudKit framework (as I see it).
 * 
 * Until this is fixed, we're forced to use this workaround.
**/
- (id)safeCopy;

@end

#pragma mark -

@interface YDBCKRecord : NSObject <NSCoding>

/**
 * This method serializes just the "system fields" of the given record.
 * That is, it won't store any of the user-created key/value pairs.
 * It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
**/
+ (NSData *)serializeRecord:(CKRecord *)record;

/**
 * Deserialize the given record data.
 *
 * If the record data came from [YDBCKRecord serializeRecord:],
 * then the returned record will only contain the "system fields".
**/
+ (CKRecord *)deserializeRecord:(NSData *)data;

#pragma mark Instance

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readonly) CKRecord *record;

@end
