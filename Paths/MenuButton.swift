//
//  MenuButton.swift
//  Paths
//
//  Created by Mark Porcella on 5/28/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import Foundation
import MapKit

class MenuButton: UIButton {
    
     init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 105, height: 30))
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = ColorConstants.LightGreen
        self.setTitleColor(UIColor.black, for: UIControlState())
        self.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        self.layer.cornerRadius = 5
        self.layer.borderWidth = 1
        self.layer.borderColor = UIColor.black.cgColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
