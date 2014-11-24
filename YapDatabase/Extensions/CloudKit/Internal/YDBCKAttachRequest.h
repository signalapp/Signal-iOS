#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>


@interface YDBCKAttachRequest : NSObject

@property (nonatomic, strong, readwrite) CKRecord *record;
@property (nonatomic, copy,   readwrite) NSString *databaseIdentifier;
@property (nonatomic, assign, readwrite) BOOL shouldUploadRecord;

@end
