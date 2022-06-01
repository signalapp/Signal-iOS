import UIKit

final class ReactionListSheet : BaseVC {
    private let reactions: [ReactMessage]
    private var reactionMap: OrderedDictionary<String, [ReactMessage]> = OrderedDictionary()
    
    // MARK: Components
    
    lazy var contentView: UIView = {
        let result = UIView()
        result.layer.borderWidth = 0.5
        result.layer.borderColor = Colors.border.withAlphaComponent(0.5).cgColor
        result.backgroundColor = Colors.modalBackground
        return result
    }()
    
    lazy var reactionContainer: UIStackView = {
        let result = UIStackView()
        let spacing = Values.smallSpacing
        result.spacing = spacing
        result.layoutMargins = UIEdgeInsets(top: spacing, leading: spacing, bottom: spacing, trailing: spacing)
        result.isLayoutMarginsRelativeArrangement = true
        return result
    }()
    
    // MARK: Lifecycle
    
    init(for reactions: [ReactMessage]) {
        self.reactions = reactions
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipeGestureRecognizer.direction = .down
        view.addGestureRecognizer(swipeGestureRecognizer)
        populateData()
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        view.addSubview(contentView)
        contentView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.bottom ], to: view)
        contentView.set(.height, to: 440)
        populateContentView()
    }
    
    private func populateContentView() {
        // Reactions container
        let scrollableContainer = UIScrollView(wrapping: reactionContainer, withInsets: .zero)
        scrollableContainer.showsVerticalScrollIndicator = false
        scrollableContainer.showsHorizontalScrollIndicator = false
        scrollableContainer.set(.height, to: 48)
        for reaction in reactionMap.orderedItems {
            let reactionView = ReactionButton(emoji: reaction.0, value: reaction.1.count, largeSize: true)
            reactionContainer.addArrangedSubview(reactionView)
        }
        contentView.addSubview(scrollableContainer)
        scrollableContainer.pin([ UIView.VerticalEdge.top, UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: contentView)
        // Line
        let lineView = UIView()
        lineView.backgroundColor = Colors.border.withAlphaComponent(0.5)
        lineView.set(.height, to: 0.5)
        contentView.addSubview(lineView)
        lineView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: contentView)
        lineView.pin(.top, to: .bottom, of: scrollableContainer)
        
    }
    
    private func populateData() {
        for reaction in reactions {
            if let emoji = reaction.emoji {
                if !reactionMap.hasValue(forKey: emoji) { reactionMap.append(key: emoji, value: []) }
                var value = reactionMap.value(forKey: emoji)!
                value.append(reaction)
                reactionMap.replace(key: emoji, value: value)
            }
        }
    }
    
    // MARK: Interaction
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            close()
        }
    }

    @objc func close() {
        dismiss(animated: true, completion: nil)
    }
}
