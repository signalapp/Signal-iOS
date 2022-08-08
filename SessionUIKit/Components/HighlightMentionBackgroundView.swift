// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension NSAttributedString.Key {
    static let currentUserMentionBackgroundColor: NSAttributedString.Key = NSAttributedString.Key(rawValue: "currentUserMentionBackgroundColor")
    static let currentUserMentionBackgroundCornerRadius: NSAttributedString.Key = NSAttributedString.Key(rawValue: "currentUserMentionBackgroundCornerRadius")
    static let currentUserMentionBackgroundPadding: NSAttributedString.Key = NSAttributedString.Key(rawValue: "currentUserMentionBackgroundPadding")
}

public class HighlightMentionBackgroundView: UIView {
    weak var targetLabel: UILabel?
    var maxPadding: CGFloat = 0
    
    init(targetLabel: UILabel) {
        self.targetLabel = targetLabel
        
        super.init(frame: .zero)
        
        self.isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Functions
    
    public func calculateMaxPadding(for attributedText: NSAttributedString) -> CGFloat {
        var allMentionRadii: [CGFloat?] = []
        let path: CGMutablePath = CGMutablePath()
        path.addRect(CGRect(
            x: 0,
            y: 0,
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let frame: CTFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedText.length), path, nil)
        let lines: [CTLine] = frame.lines

        lines.forEach { line in
            let runs: [CTRun] = line.ctruns
            
            runs.forEach { run in
                let attributes: NSDictionary = CTRunGetAttributes(run)
                allMentionRadii.append(
                    attributes
                        .value(forKey: NSAttributedString.Key.currentUserMentionBackgroundPadding.rawValue) as? CGFloat
                )
            }
        }
        
        let maxRadii: CGFloat? = allMentionRadii
            .compactMap { $0 }
            .max()
        
        return (maxRadii ?? 0)
    }
    
    // MARK: - Drawing
    
    override public func draw(_ rect: CGRect) {
        guard
            let targetLabel: UILabel = self.targetLabel,
            let attributedText: NSAttributedString = targetLabel.attributedText,
            let context = UIGraphicsGetCurrentContext()
        else { return }
        
        // Need to invery the Y axis because iOS likes to render from the bottom left instead of the top left
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
       
        // Note: Calculations MUST happen based on the 'targetLabel' size as this class has extra padding
        // which can result in calculations being off
        let path = CGMutablePath()
        let size = targetLabel.sizeThatFits(CGSize(width: targetLabel.bounds.width, height: .greatestFiniteMagnitude))
        path.addRect(CGRect(x: 0, y: 0, width: size.width, height: size.height), transform: .identity)

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText as CFAttributedString)
        let frame: CTFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedText.length), path, nil)
        let lines: [CTLine] = frame.lines

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        
        for lineIndex in 0..<lines.count {
            let line = lines[lineIndex]
            let runs: [CTRun] = line.ctruns
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            
            for run in runs {
                let attributes: NSDictionary = CTRunGetAttributes(run)
                
                guard let mentionBackgroundColor: UIColor = attributes.value(forKey: NSAttributedString.Key.currentUserMentionBackgroundColor.rawValue) as? UIColor else {
                    continue
                }
                
                let maybeCornerRadius: CGFloat? = (attributes
                    .value(forKey: NSAttributedString.Key.currentUserMentionBackgroundCornerRadius.rawValue) as? CGFloat)
                let maybePadding: CGFloat? = (attributes
                    .value(forKey: NSAttributedString.Key.currentUserMentionBackgroundPadding.rawValue) as? CGFloat)
                let padding: CGFloat = (maybePadding ?? 0)
                
                let range = CTRunGetStringRange(run)
                var runBounds: CGRect = .zero
                var runAscent: CGFloat = 0
                var runDescent: CGFloat = 0
                runBounds.size.width = CGFloat(CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &runAscent, &runDescent, nil) + (padding * 2))
                runBounds.size.height = (runAscent + runDescent + (padding * 2))

                let xOffset: CGFloat = {
                    switch CTRunGetStatus(run) {
                        case .rightToLeft:
                            return CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
                            
                        default:
                            return CTLineGetOffsetForStringIndex(line, range.location, nil)
                    }
                }()
                
                // HACK: This `extraYOffset` value is a hack to resolve a weird issue where the
                // positioning seems to be slightly off every additional line of text we add (it
                // doesn't seem to be related to line spacing or anything, more related to the
                // bold mention text being positioned slightly differently from the non-bold text)
                let extraYOffset: CGFloat = (CGFloat(lineIndex) * (runDescent / 12))
                
                // Note: Changes to `origin.y` need to be inverted since the context has been flipped
                runBounds.origin.x = origins[lineIndex].x + rect.origin.x + self.maxPadding + xOffset - padding
                runBounds.origin.y = (
                    origins[lineIndex].y + rect.origin.y +
                    self.maxPadding -
                    padding -
                    runDescent -
                    extraYOffset
                )
                
                let path = UIBezierPath(roundedRect: runBounds, cornerRadius: (maybeCornerRadius ?? 0))
                mentionBackgroundColor.setFill()
                path.fill()
            }
        }
    }
}

extension CTFrame {
    var lines: [CTLine] {
        return ((CTFrameGetLines(self) as [AnyObject] as? [CTLine]) ?? [])
    }
}

extension CTLine {
    var ctruns: [CTRun] {
        return ((CTLineGetGlyphRuns(self) as [AnyObject] as? [CTRun]) ?? [])
    }
}
