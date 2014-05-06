#import "Environment.h"
#import "PhoneNumberDirectoryFilter.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "UnseenWhisperUserCell.h"

@implementation UnseenWhisperUserCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    return self;
}

- (NSString *)restorationIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithContact:(Contact *)contact {
    _nameLabel.text = [contact fullName];
    
    PhoneNumberDirectoryFilter *filter = [[[Environment getCurrent] phoneDirectoryManager] getCurrentFilter];
    BOOL foundPhoneNumber = NO;
    
    for (PhoneNumber *number in contact.parsedPhoneNumbers) {
        if ([filter containsPhoneNumber:number]) {
            foundPhoneNumber = YES;
            _numberLabel.text = [number localizedDescriptionForUser];
        }
    }
}

@end
