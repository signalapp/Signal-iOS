#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>


@interface YDBCKChangeRecord : NSObject <NSCoding, NSCopying>

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readwrite) CKRecord *record;

@property (nonatomic, assign, readwrite) BOOL needsStoreFullRecord;
@property (nonatomic, strong, readwrite) NSDictionary *originalValues;

@property (nonatomic, readonly) CKRecordID *recordID;
@property (nonatomic, readonly) NSArray *changedKeys;
@property (nonatomic, readonly) NSSet *changedKeysSet;

@end
