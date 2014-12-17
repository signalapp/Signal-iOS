
//
//  TSAttachement.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachement.h"

@implementation TSAttachement

- (instancetype)initWithIdentifier:(NSString*)identifier
                     encryptionKey:(NSData*)encryptionKey
                       contentType:(NSString*)contentType {
    self = [super initWithUniqueId:identifier];
    
    if (self) {
        _encryptionKey = encryptionKey;
        _contentType   = contentType;
    }
    
    return self;
}

+ (NSString *)collection{
    return @"TSAttachements";
}

- (NSNumber*)identifier{
    NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterDecimalStyle];
    return [f numberFromString:self.uniqueId];
}

- (BOOL)isDownloaded{
    return NO;
}

@end
