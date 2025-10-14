//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
public import SignalServiceKit
public import SignalUI

public protocol CVPollVoteDelegate: AnyObject {
    func didTapVoteOnPoll(poll: OWSPoll, optionIndex: UInt32, isUnvote: Bool)
}

public class CVPollView: ManualStackView {
    struct State: Equatable {
        let poll: OWSPoll
        let isIncoming: Bool
        let conversationStyle: ConversationStyle
        let localAci: Aci
    }

    public weak var pollVoteDelegate: CVPollVoteDelegate?

    private let subtitleStack = ManualStackView(name: "subtitleStack")
    private let questionTextLabel = CVLabel()
    private let pollLabel = CVLabel()
    private let chooseLabel = CVLabel()

    private static let measurementKey_outerStack = "CVPollView.measurementKey_outerStack"
    private static let measurementKey_subtitleStack = "CVPollView.measurementKey_subtitleStack"
    private static let measurementKey_optionStack = "CVPollView.measurementKey_optionStack"
    fileprivate static let measurementKey_optionRowOuterStack = "CVPollView.measurementKey_optionOuterRowStack"
    fileprivate static let measurementKey_optionRowInnerStack = "CVPollView.measurementKey_optionInnerRowStack"

    /*
     OuterStack
     [
        [ Question Text ]
        [ Poll, Select One/multiple ] <-- SubtitleStack
        OptionStack
        [
            OptionRowOuterStack
            [
                [checkbox, option text] <-- OptionRowInnerStack
                progressBar
            ]

            OptionRowOuterStack
            [
                [checkbox, option text] <-- OptionRowInnerStack
                progressBar
            ]

            ...
        ]
     ]
     */
    fileprivate struct Configurator {
        let poll: OWSPoll
        let textColor: UIColor
        let subtitleColor: UIColor
        var detailColor: UIColor

        init(state: CVPollView.State) {
            self.poll = state.poll
            self.textColor = state.conversationStyle.bubbleTextColor(isIncoming: state.isIncoming)
            self.subtitleColor = state.conversationStyle.bubbleSecondaryTextColor(isIncoming: state.isIncoming)
            self.detailColor = state.isIncoming ? UIColor.Signal.ultramarine : textColor
        }

        var outerStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .leading,
                              spacing: 2,
                              layoutMargins: UIEdgeInsets(hMargin: 4, vMargin: 6))
        }

        var questionTextLabelConfig: CVLabelConfig {
            return CVLabelConfig.unstyledText(
                poll.question,
                font: UIFont.dynamicTypeHeadline,
                textColor: textColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
        }

        var subtitleStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .horizontal,
                              alignment: .leading,
                              spacing: 4,
                              layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 0))
        }

        var pollSubtitleTextLabelConfig: CVLabelConfig {
            return CVLabelConfig.unstyledText(
                OWSLocalizedString("POLL_LABEL", comment: "Label specifying the message type as a poll"),
                font: UIFont.dynamicTypeFootnote,
                textColor: textColor.withAlphaComponent(0.8),
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
        }

        var chooseSubtitleTextLabelConfig: CVLabelConfig {
            var selectLabel: String
            if poll.isEnded {
                selectLabel = OWSLocalizedString("POLL_FINAL_RESULTS_LABEL", comment: "Label specifying the poll is finished and these are the final results")
            } else {
                selectLabel = poll.allowsMultiSelect ? OWSLocalizedString(
                    "POLL_SELECT_LABEL_MULTIPLE", comment: "Label specifying the user can select more than one option"
                ) : OWSLocalizedString(
                    "POLL_SELECT_LABEL_SINGULAR",
                    comment: "Label specifying the user can select one option"
                )
            }

            return CVLabelConfig.unstyledText(
                selectLabel,
                font: UIFont.dynamicTypeFootnote,
                textColor: textColor.withAlphaComponent(0.8),
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
        }

        var optionStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .leading,
                              spacing: 8,
                              layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 16))
        }

        var optionRowOuterStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .leading,
                              spacing: 8,
                              layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 4))
        }

        let checkBoxSize = CGSize(square: 22)

        let circleSize = CGSize(square: 2)

        func buildOptionRowInnerStackConfig(voteLabelWidth: Double) -> CVStackViewConfig {
            CVStackViewConfig(axis: .horizontal,
                              alignment: .leading,
                              spacing: 8,
                              layoutMargins: UIEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: voteLabelWidth))
        }
    }

    static func buildState(
        poll: OWSPoll,
        isIncoming: Bool,
        conversationStyle: ConversationStyle,
        localAci: Aci
    ) -> State {
        return State(poll: poll,
                     isIncoming: isIncoming,
                     conversationStyle: conversationStyle,
                     localAci: localAci
        )
    }

    private static func localizedNumber(from votes: Int) -> String {
        let formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f
        }()

        return formatter.string(from: NSNumber(value: votes))!
    }

    private static func voteLabelWidthWithPadding(localizedVotes: String) -> Double {
        let attributes = [NSAttributedString.Key.font: UIFont.dynamicTypeBody]
        let textSize = localizedVotes.size(withAttributes: attributes)
        return textSize.width + 4
    }

    static func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder,
        state: CVPollView.State
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let poll = state.poll
        let configurator = Configurator(state: state)
        let maxLabelWidth = (maxWidth - (configurator.outerStackConfig.layoutMargins.totalWidth))
        var outerStackSubviewInfos = [ManualStackSubviewInfo]()

        // MARK: - Question

        let questionTextLabelConfig = configurator.questionTextLabelConfig
        let questionSize = CVText.measureLabel(config: questionTextLabelConfig,
                                                   maxWidth: maxLabelWidth)

        outerStackSubviewInfos.append(questionSize.asManualSubviewInfo)

        // MARK: - Subtitle

        var subtitleStackSubviews = [ManualStackSubviewInfo]()

        let pollSubtitleLabelConfig = configurator.pollSubtitleTextLabelConfig
        let pollSubtitleSize = CVText.measureLabel(
            config: pollSubtitleLabelConfig,
            maxWidth: maxLabelWidth
        )
        subtitleStackSubviews.append(pollSubtitleSize.asManualSubviewInfo)

        // Small bullet
        subtitleStackSubviews.append(configurator.circleSize.asManualSubviewInfo(hasFixedSize: true))

        let chooseSubtitleLabelConfig = configurator.chooseSubtitleTextLabelConfig
        let chooseSubtitleSize = CVText.measureLabel(
            config: chooseSubtitleLabelConfig,
            maxWidth: maxLabelWidth
        )
        subtitleStackSubviews.append(chooseSubtitleSize.asManualSubviewInfo)

        let subtitleStackMeasurement = ManualStackView.measure(
            config: configurator.subtitleStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: measurementKey_subtitleStack,
            subviewInfos: subtitleStackSubviews
        )

        outerStackSubviewInfos.append(subtitleStackMeasurement.measuredSize.asManualSubviewInfo)

        // MARK: - Options

        var optionStackRows = [ManualStackSubviewInfo]()
        for option in poll.sortedOptions() {
            let optionTextConfig = CVLabelConfig.unstyledText(
                option.text,
                font: UIFont.dynamicTypeBody,
                textColor: configurator.textColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )

            let hasLocalUserVoted = option.localUserHasVoted(localAci: state.localAci)

            // When the poll is ended, the checkbox should be removed except for options
            // the local user voted for. Those checkboxes should be shifted right.
            // In order to make sure they don't overlap with vote count, we need to measure
            // the vote count width and update the option row stack config trailing
            // spacing accordingly.
            let checkboxSize = poll.isEnded && !hasLocalUserVoted ? 0 : configurator.checkBoxSize.width

            let localizedVotesString = localizedNumber(from: option.acis.count)
            let voteLabelWidth = voteLabelWidthWithPadding(localizedVotes: localizedVotesString)
            let innerStackConfig = configurator.buildOptionRowInnerStackConfig(voteLabelWidth: voteLabelWidth)

            let maxOptionLabelWidth = (maxLabelWidth - (innerStackConfig.layoutMargins.right +
                                                        checkboxSize +
                                                        innerStackConfig.spacing))

            let optionLabelTextSize = CVText.measureLabel(
                config: optionTextConfig,
                maxWidth: maxOptionLabelWidth
            )

            // Even though the text may not take up the whole width, we should use the max
            // row size because the number of votes will be displayed on the far side.
            let optionRowSize = CGSize(
                width: maxOptionLabelWidth,
                height: optionLabelTextSize.height
            )

            var subViewInfos: [ManualStackSubviewInfo] = []
            if poll.isEnded {
                subViewInfos = [optionRowSize.asManualSubviewInfo]
                if hasLocalUserVoted {
                    subViewInfos.append(configurator.checkBoxSize.asManualSubviewInfo(hasFixedSize: true))
                }
            } else {
                subViewInfos = [configurator.checkBoxSize.asManualSubviewInfo(hasFixedSize: true), optionRowSize.asManualSubviewInfo]
            }

            let optionRowInnerMeasurement = ManualStackView.measure(
                config: innerStackConfig,
                measurementBuilder: measurementBuilder,
                measurementKey: measurementKey_optionRowInnerStack + String(option.optionIndex),
                subviewInfos: subViewInfos
            )

            let progressBarSize = CGSize(width: maxLabelWidth, height: 8)
            let optionRowOuterMeasurement = ManualStackView.measure(
                config: configurator.optionRowOuterStackConfig,
                measurementBuilder: measurementBuilder,
                measurementKey: measurementKey_optionRowOuterStack + String(option.optionIndex),
                subviewInfos: [optionRowInnerMeasurement.measuredSize.asManualSubviewInfo, progressBarSize.asManualSubviewInfo]
            )

            optionStackRows.append(optionRowOuterMeasurement.measuredSize.asManualSubviewInfo)
        }

        let optionStackMeasurement = ManualStackView.measure(
            config: configurator.optionStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_optionStack,
            subviewInfos: optionStackRows
        )
        outerStackSubviewInfos.append(optionStackMeasurement.measuredSize.asManualSubviewInfo)

        // MARK: - Outer Stack

        let outerStackMeasurement = ManualStackView.measure(
            config: configurator.outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: outerStackSubviewInfos
        )

        return outerStackMeasurement.measuredSize
    }

    private func buildSubtitleStack(configurator: Configurator, cellMeasurement: CVCellMeasurement) {
        let pollLabelConfig = configurator.pollSubtitleTextLabelConfig
        pollLabelConfig.applyForRendering(label: pollLabel)

        let chooseLabelConfig = configurator.chooseSubtitleTextLabelConfig
        chooseLabelConfig.applyForRendering(label: chooseLabel)

        let circleView = UIView()
        circleView.backgroundColor = configurator.subtitleColor
        circleView.layer.cornerRadius = configurator.circleSize.width / 2

        let circleContainer = ManualLayoutView(name: "circleContainer")
        circleContainer.addSubview(circleView, withLayoutBlock: { [weak self] _ in
            guard let self = self else {
                return
            }

            let subviewFrame = CGRect(
                origin: CGPoint(x: 0, y: chooseLabel.bounds.midY),
                size: configurator.circleSize
            )
            Self.setSubviewFrame(subview: circleView, frame: subviewFrame)
        })

        subtitleStack.configure(
            config: configurator.subtitleStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_subtitleStack,
            subviews: [pollLabel, circleContainer, chooseLabel]
        )
    }

    func configureForRendering(
        state: CVPollView.State,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate
    ) {
        let poll = state.poll

        let configurator = Configurator(state: state)
        var outerStackSubViews = [UIView]()

        let questionTextLabelConfig = configurator.questionTextLabelConfig
        questionTextLabelConfig.applyForRendering(label: questionTextLabel)
        outerStackSubViews.append(questionTextLabel)

        buildSubtitleStack(configurator: configurator, cellMeasurement: cellMeasurement)
        outerStackSubViews.append(subtitleStack)

        var optionSubviews = [UIView]()
        for option in poll.sortedOptions() {
            let row = PollOptionView(
                configurator: configurator,
                cellMeasurement: cellMeasurement,
                pollOption: option,
                totalVotes: poll.totalVotes(),
                hasLocalUserAlreadyVoted: option.localUserHasVoted(localAci: state.localAci),
                pollVoteHandler: { [weak self, weak componentDelegate] voteType in
                    self?.handleVote(
                        for: option,
                        on: poll,
                        voteType: voteType,
                        delegate: componentDelegate
                    )
                },
                pollIsEnded: poll.isEnded
            )
            optionSubviews.append(row)
        }

        let optionsStack = ManualStackView(name: "optionsStack")
        optionsStack.configure(
            config: configurator.optionStackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_optionStack,
            subviews: optionSubviews
        )
        outerStackSubViews.append(optionsStack)

        self.configure(config: configurator.outerStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_outerStack,
                              subviews: outerStackSubViews)
    }

    private func handleVote(
        for option: OWSPoll.OWSPollOption,
        on poll: OWSPoll,
        voteType: VoteType,
        delegate: CVPollVoteDelegate?
    ) {
        delegate?.didTapVoteOnPoll(
            poll: poll,
            optionIndex: option.optionIndex,
            isUnvote: voteType == .unvote
        )
    }

    public override func reset() {
        super.reset()

        questionTextLabel.text = nil

        pollLabel.text = nil
        chooseLabel.text = nil
        subtitleStack.reset()

        // TODO: reset everything else
    }

    // MARK: - PollOptionView
    /// Class representing an option row which displays and updates selected state

    enum VoteType {
        case unvote
        case vote
    }

    class PollOptionView: ManualStackView {
        typealias OWSPollOption = OWSPoll.OWSPollOption

        let pollVoteHandler: (VoteType) -> Void

        let checkbox = CVButton()
        let optionText = CVLabel()
        let innerStack = ManualStackView(name: "innerStack")
        let numVotesLabel = CVLabel()
        let innerStackContainer = ManualLayoutView(name: "innerStackContainer")
        let progressFill = UIView()
        let progressBarBackground = UIView()
        let progressBarContainer = ManualLayoutView(name: "progressBarContainer")

        fileprivate init(
            configurator: Configurator,
            cellMeasurement: CVCellMeasurement,
            pollOption: OWSPollOption,
            totalVotes: Int,
            hasLocalUserAlreadyVoted: Bool,
            pollVoteHandler: @escaping (VoteType) -> Void,
            pollIsEnded: Bool
        ) {
            self.pollVoteHandler = pollVoteHandler

            super.init(name: "PollOptionView")
            buildOptionRowStack(
                configurator: configurator,
                cellMeasurement: cellMeasurement,
                option: pollOption.text,
                index: pollOption.optionIndex,
                votes: pollOption.acis.count,
                totalVotes: totalVotes,
                hasLocalUserAlreadyVoted: hasLocalUserAlreadyVoted,
                isPending: pollOption.isPending,
                pollIsEnded: pollIsEnded
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func didTapCheckbox() {
            checkbox.isSelected.toggle()
            pollVoteHandler(checkbox.isSelected ? .vote : .unvote)
        }

        private func buildProgressBar(votes: Int, totalVotes: Int, detailColor: UIColor) {
            progressFill.backgroundColor = detailColor
            progressFill.layer.cornerRadius = 5
            progressBarBackground.backgroundColor = detailColor.withAlphaComponent(0.5)
            progressBarBackground.layer.cornerRadius = 5

            progressBarContainer.addSubview(progressBarBackground, withLayoutBlock: { [weak self] _ in
                    guard let self = self, let superview = progressBarBackground.superview else {
                        owsFailDebug("Missing superview.")
                        return
                    }

                // The progress bar should start under the text, not the checkbox, so we need to shift it
                // over to be under the optionText, and remove that offset from the total size.
                let progressBarOffset = optionText.frame.x
                let adjustedSize = CGSize(width: superview.bounds.width - progressBarOffset, height: superview.bounds.height)
                let subviewFrame = CGRect(
                    origin: CGPoint(x: superview.bounds.origin.x + progressBarOffset, y: superview.bounds.origin.y),
                    size: adjustedSize)
                Self.setSubviewFrame(subview: progressBarBackground, frame: subviewFrame)
            })

            // No need to render progress fill if votes are 0
            if votes <= 0 {
                return
            }

            progressBarContainer.addSubview(progressFill, withLayoutBlock: { [weak self] _ in
                guard let self = self, let superview = progressFill.superview else {
                    owsFailDebug("Missing superview.")
                    return
                }

                let percent = Float(votes) / Float(totalVotes)

                // The progress bar should start under the text, not the checkbox, so we need to shift it
                // over to be under the optionText, and remove that offset from the total size.
                let progressBarOffset = optionText.frame.x
                let numVotesBarFill = CGFloat(percent) * (superview.bounds.width - progressBarOffset)
                let subviewFrame = CGRect(
                    origin: CGPoint(x: progressBarOffset, y: superview.bounds.origin.y),
                    size: CGSize(width: numVotesBarFill, height: superview.bounds.height)
                )
                Self.setSubviewFrame(subview: progressFill, frame: subviewFrame)
            })
        }

        private func buildOptionRowStack(
            configurator: Configurator,
            cellMeasurement: CVCellMeasurement,
            option: String,
            index: UInt32,
            votes: Int,
            totalVotes: Int,
            hasLocalUserAlreadyVoted: Bool,
            isPending: Bool,
            pollIsEnded: Bool
        ) {
            checkbox.setImage(UIImage(named: Theme.iconName(.checkCircleFill)), for: .selected)
            checkbox.setImage(UIImage(named: Theme.iconName(.circle)), for: .normal)
            checkbox.tintColor = configurator.detailColor
            checkbox.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCheckbox)))

            checkbox.isSelected = hasLocalUserAlreadyVoted

            // TODO: animate when pending.

            let optionTextConfig = CVLabelConfig.unstyledText(
                option,
                font: UIFont.dynamicTypeBody,
                textColor: configurator.textColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
            optionTextConfig.applyForRendering(label: optionText)

            var subviews: [UIView] = []
            if pollIsEnded {
                checkbox.isUserInteractionEnabled = false
                subviews = [optionText]
                if hasLocalUserAlreadyVoted {
                    subviews.append(checkbox)
                }
            } else {
                subviews = [checkbox, optionText]
            }

            let localizedVotesString = localizedNumber(from: votes)
            let voteLabelWidth = voteLabelWidthWithPadding(localizedVotes: localizedVotesString)
            let innerStackConfig = configurator.buildOptionRowInnerStackConfig(voteLabelWidth: voteLabelWidth)

            innerStack.configure(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: measurementKey_optionRowInnerStack + String(index),
                subviews: subviews
            )

            innerStackContainer.addSubviewToFillSuperviewEdges(innerStack)

            let numVotesConfig = CVLabelConfig.unstyledText(
                localizedVotesString,
                font: UIFont.dynamicTypeBody,
                textColor: configurator.textColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping,
                textAlignment: .right
            )
            numVotesConfig.applyForRendering(label: numVotesLabel)
            innerStackContainer.addSubviewToFillSuperviewEdges(numVotesLabel)

            buildProgressBar(votes: votes, totalVotes: totalVotes, detailColor: configurator.detailColor)

            configure(
                config: configurator.optionRowOuterStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: measurementKey_optionRowOuterStack + String(index),
                subviews: [innerStackContainer, progressBarContainer]
            )
        }
    }
}
