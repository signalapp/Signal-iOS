#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>


@interface YDBCKAttachRequest : NSObject

@property (nonatomic, copy,   readwrite) NSString *databaseIdentifier;
@property (nonatomic, strong, readwrite) CKRecord *record;

@property (nonatomic, assign, readwrite) BOOL shouldUploadRecord;

@end
