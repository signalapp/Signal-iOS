
final class MessagesTableView : UITableView {
    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
        initialize()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }
    
    private func initialize() {
        register(VisibleMessageCell.self, forCellReuseIdentifier: VisibleMessageCell.identifier)
        register(InfoMessageCell.self, forCellReuseIdentifier: InfoMessageCell.identifier)
        register(TypingIndicatorCell.self, forCellReuseIdentifier: TypingIndicatorCell.identifier)
        separatorStyle = .none
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        keyboardDismissMode = .interactive
    }
}
