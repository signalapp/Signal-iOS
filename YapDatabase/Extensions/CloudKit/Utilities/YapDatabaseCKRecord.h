#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@interface YapDatabaseCKRecord : NSObject <NSCoding>

/**
 * This method serializes just the "system fields" of the given record.
 * That is, it won't store any of the user-created key/value pairs.
 * It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
**/
+ (NSData *)serializeRecord:(CKRecord *)record;

/**
 * Deserialized the given record data.
 *
 * If the record data came from [YapDatabaseCKRecord serializeRecord:],
 * then the returned record will only contain the "system fields".
**/
+ (CKRecord *)deserializeRecord:(NSData *)data;

/**
 * Returns a "sanitized" copy of the given record.
 * That is, a copy that ONLY includes the "system fields" of the record.
 * It will NOT contain any key/value pairs from the original record.
**/
+ (CKRecord *)sanitizedRecord:(CKRecord *)record;

#pragma mark Instance

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readonly) CKRecord *record;

@end
