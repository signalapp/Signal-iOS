//
//  JSQMessagesCollectionViewCell+menuBarItems.m
//  Signal
//
//  Created by Frederic Jacobs on 26/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesCollectionViewCell+menuBarItems.h"

@implementation JSQMessagesCollectionViewCell (menuBarItems)

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(delete:)) {
        return YES;
    }
    
    return [super canPerformAction:action withSender:sender];
}

- (void)delete:(id)sender
{
    [self performSelectorOnParentCollectionView:@selector(delete:)
                                     withSender:sender];
}

- (void)performSelectorOnParentCollectionView:(SEL)selector
                                   withSender:(id)sender {
    UIView *view = self;
    do {
        view = view.superview;
    } while (![view isKindOfClass:[UICollectionView class]]);
    UICollectionView *collectionView = (UICollectionView *)view;
    NSIndexPath *indexPath = [collectionView indexPathForCell:self];
    
    if (collectionView.delegate &&
        [collectionView.delegate respondsToSelector:@selector(collectionView:
                                                              performAction:
                                                              forItemAtIndexPath:
                                                              withSender:)])
        
        [collectionView.delegate collectionView:collectionView
                                  performAction:selector
                             forItemAtIndexPath:indexPath
                                     withSender:sender];
}   

@end
