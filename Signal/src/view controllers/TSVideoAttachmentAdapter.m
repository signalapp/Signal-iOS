//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"

#import "UIDevice+TSHardwareVersion.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"

@interface TSVideoAttachmentAdapter ()

@property UIImage *image;

@property (strong, nonatomic) UIImageView *cachedImageView;
@end

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment{
    self = [super initWithFileURL:[attachment videoURL] isReadyToPlay:YES];
    
    if (self) {
        _image           = attachment.image;
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        
    }
    return self;
}

-(BOOL) isImage{
    return NO;
}

- (void)dealloc
{
    _image = nil;
    _cachedImageView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

@end
