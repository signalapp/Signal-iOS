//
//  SlugCell.swift
//  Forsta
//
//  Created by Mark Descalzo on 5/23/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit

protocol SlugCellDelegate {
    func deleteButtonTappedOnSlug(sender: Any)
}

class SlugCell: UICollectionViewCell {
    
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        layer.cornerRadius = frame.size.height/10.0
    }

    var slug: String? {
        didSet {
            if let slug = slug {
                slugLabel.text = slug
                slugLabel.sizeToFit()
            }
        }
    }
    
    var delegate: SlugCellDelegate?

    @IBOutlet weak var slugLabel: UILabel!
    @IBOutlet weak private var deleteButton: UIButton!
    
    @IBAction func didTapDeleteButton(_ sender: Any) {
        self.delegate?.deleteButtonTappedOnSlug(sender: slug as Any)
    }
}
