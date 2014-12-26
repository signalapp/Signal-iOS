//
//  TSattachmentStream.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "UIImage+contentTypes.h"

NSString * const TSAttachementFileRelationshipEdge = @"TSAttachementFileEdge";

@interface TSAttachmentStream ()

@property (nonatomic) NSString *attachmentPath;

@end

@implementation TSAttachmentStream

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType{
    self = [super initWithIdentifier:identifier encryptionKey:key contentType:contentType];

    [[NSFileManager defaultManager] createFileAtPath:_attachmentPath contents:data attributes:nil];
    
    return self;
}

- (BOOL)isDownloaded{
    return YES;
}

- (NSArray *)yapDatabaseRelationshipEdges {
    YapDatabaseRelationshipEdge *attachmentFileEdge = [YapDatabaseRelationshipEdge edgeWithName:TSAttachementFileRelationshipEdge
                                                                            destinationFilePath:[self filePath]
                                                                                nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
    
    return @[attachmentFileEdge];
}

+ (NSString*)attachmentsFolder {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL *fileURL             = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *path             = [fileURL path];
    NSString *attachmentFolder = [path stringByAppendingFormat:@"/Attachments"];
    
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:attachmentFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
        DDLogError(@"Failed to create attachments directory: %@", error.description);
    }
    
    return attachmentFolder;
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

- (BOOL)isVideo{
    if ([self.contentType containsString:@"video/"]) {
        return YES;
    } else{
        return NO;
    }
}

- (UIImage*)image{
    if (![self isImage]) {
        return nil;
    }
    
    return [UIImage imageWithContentsOfFile:self.filePath];
}

@end
