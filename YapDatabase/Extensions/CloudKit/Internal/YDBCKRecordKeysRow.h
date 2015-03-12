#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

/**
 * This class represents a row in the RecordKeys table.
**/
@interface YDBCKRecordKeysRow : NSObject

+ (YDBCKRecordKeysRow *)hashRecordKeys:(CKRecord *)record;

- (instancetype)initWithHash:(NSString *)hash keys:(NSArray *)keys;

@property (nonatomic, strong, readonly) NSString *hash;
@property (nonatomic, strong, readonly) NSArray *keys;

@property (nonatomic, assign, readwrite) BOOL needsInsert;

@end
