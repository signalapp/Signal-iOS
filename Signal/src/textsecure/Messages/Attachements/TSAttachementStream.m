//
//  TSAttachementStream.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachementStream.h"

@interface TSAttachementStream ()

@property (nonatomic) NSString *path;

@end

@implementation TSAttachementStream

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType{
    self = [super initWithIdentifier:identifier encryptionKey:key contentType:contentType];
    
    NSString *path = [self filePath];
    [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
    
    return self;
}

- (BOOL)isDownloaded{
    return YES;
}

+ (NSString*)attachmentsFolder {
    NSFileManager* fileManager  = [NSFileManager defaultManager];
    NSURL *fileURL              = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *path              = [fileURL path];
    NSString *attachementFolder = [path stringByAppendingFormat:@"/Attachements"];
    
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:attachementFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
        DDLogError(@"Failed to create attachments directory: %@", error.description);
    }

    return attachementFolder;
}

- (NSString*)filePath {
    return [[[self class] attachmentsFolder] stringByAppendingFormat:@"/%@", self.uniqueId];
}

- (BOOL)isImage{
    if ([self.contentType containsString:@"image/"]) {
        return YES;
    } else{
        return NO;
    }
}

- (UIImage*)image{
    if (![self isImage]) {
        return nil;
    }
    
    return [UIImage imageWithContentsOfFile:[self filePath]];
}

@end
