//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesCollectionViewCell+OWS.h"
#import "OWSExpirableMessageView.h"
#import "OWSMessageCollectionViewCell.h"
#import "OWSMessageMediaAdapter.h"
#import <JSQMessagesViewController/JSQMessagesCollectionViewCellOutgoing.h>

NS_ASSUME_NONNULL_BEGIN

@class JSQMediaItem;

@interface OWSOutgoingMessageCollectionViewCell
    : JSQMessagesCollectionViewCellOutgoing <OWSExpirableMessageView, OWSMessageCollectionViewCell>

@property (nonatomic, nullable) id<OWSMessageMediaAdapter> mediaAdapter;

@end

NS_ASSUME_NONNULL_END
