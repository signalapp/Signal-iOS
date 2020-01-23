
@objc(LKMentionCandidateSelectionViewDelegate)
protocol MentionCandidateSelectionViewDelegate {
    
    func handleMentionCandidateSelected(_ mentionCandidate: Mention, from mentionCandidateSelectionView: MentionCandidateSelectionView)
}
