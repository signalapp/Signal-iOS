
@objc(LKGeneralUtilities)
final class GeneralUtilities : NSObject {
    
    private override init() { }

    @objc static func getSessionPublicChatNotice() -> String {
        return """
        Welcome to the Session public chat! In order for this forum to be a fun environment, full of robust and constructive discussion and inclusive of everyone, please read and follow the rules below.

        1. Please Keep Talk Relevant to Topic and Add Value to the Discussion.
            (No Referral Links, Spamming, Off Topic Discussion)

        2. You don't have to love everyone, but be civil.
            (No Baiting, Excessively Partisan Arguments, Threats, and so on. Use common sense.)

        3. Do not be a shill.
        Comparison and criticism is reasonable, but blatant shilling of anything you work for, work on, or own is not.

        4. Don't post explicit content - be it excessively offensive language, sexual, or violent. Any form of bigotry including racism, sexism, transphobia, homophobia, ableism, fatphobia, classism will NOT be tolerated.

        If you break these rules, you’ll be warned by an admin. If your behaviour doesn’t improve, you will be removed from the public chat. Admins reserve the right to remove anyone violating these rules.

        We want to keep this group a pleasant and supportive space for everyone.

        If you experience any anti-social behaviour or have an issue with these rules, please contact an admin.
        """
    }
}
