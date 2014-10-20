#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@interface YapDatabaseCKRecord : NSObject <NSCoding>

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readonly) CKRecord *record;

@end
