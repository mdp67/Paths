//
//  RouteTableViewCell.swift
//  Paths
//
//  Created by Mark Porcella on 6/1/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import UIKit

protocol RouteTVCDelegate {
    func deletePressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath)
    func editPressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath)
    func navPressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath)
}

class RouteTableViewCell: UITableViewCell {

    fileprivate struct Constants {
        static let editSegue = "unwindEditRoute"
        static let navigateSegue = "NavigateFromRoutes"
    }
    
//    fileprivate enum routeSortOrder: String {
//        case name, distanceMeters, dateCreated, dateAccessed
//    }

    
    var delegate: RouteTVCDelegate?
    var indexPath: IndexPath!
    
    @IBOutlet weak var labelName: UILabel!
    @IBOutlet weak var labelDistance: UILabel!
    @IBOutlet weak var buttonStart: UIButton!
    
    
    override func awakeFromNib() { super.awakeFromNib() }

    override func setSelected(_ selected: Bool, animated: Bool) { super.setSelected(selected, animated: animated)  }

    @IBAction func onDelete(_ sender: UIButton) { delegate?.deletePressedAt(RouteTVC: self, atIndexPath: indexPath) }

    @IBAction func edit(_ sender: UIButton) { delegate?.editPressedAt(RouteTVC: self, atIndexPath: indexPath) }
    
    @IBAction func start(_ sender: UIButton) { delegate?.navPressedAt(RouteTVC: self, atIndexPath: indexPath) }
    
    
    
    
    
    
    
    
    
}
