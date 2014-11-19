#import <UIKit/UIKit.h>

#define SEARCH_BAR_DEFAULT_EMPTY_STRING @""

@class SearchBarTitleView;

@protocol SearchBarTitleViewDelegate <NSObject>

- (void)searchBarTitleView:(SearchBarTitleView*)view didSearchForTerm:(NSString*)term;
- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView*)view;
- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView*)view;

@end

@interface SearchBarTitleView : UIView <UITextFieldDelegate>

@property (strong, nonatomic) IBOutlet UILabel* titleLabel;
@property (strong, nonatomic) IBOutlet UIView* searchBarContainer;
@property (strong, nonatomic) IBOutlet UITextField* searchTextField;
@property (strong, nonatomic) IBOutlet UIButton* searchButton;
@property (strong, nonatomic) IBOutlet UIButton* cancelButton;
@property (strong, nonatomic) IBOutlet UIButton* menuButton;
@property (weak, nonatomic)   IBOutlet id<SearchBarTitleViewDelegate> delegate;

- (void)updateAutoCorrectionType;

@end
