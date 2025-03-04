//
//  RouteCD+CoreDataClass.swift
//  Paths
//
//  Created by Mark Porcella on 12/11/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//



import Foundation
import CoreData

@objc(RouteCD)
public class RouteCD: NSManagedObject {
    
    class func routeCDFromRoute(_ route: Route, inMOC moc: NSManagedObjectContext, dateCreated: Date? = nil) -> RouteCD? {
        
        if let newRouteCD = NSEntityDescription.insertNewObject(forEntityName: "RouteCD", into: moc) as? RouteCD {
            newRouteCD.dateCreated = dateCreated as NSDate? ?? Date() as NSDate
            newRouteCD.dateAccessed = Date() as NSDate
            if let routeName = route.name , routeName == "" || route.name == nil {
                let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .short; dateFormatter.timeStyle = .short
                route.name = dateFormatter.string(from: Date())
            }
            newRouteCD.name = route.name
            newRouteCD.travelMode = Int16(UserDefaults().integer(forKey: ConstantStrings.selectedNavType))
            if let ttlDstc = route.totalDistance {
                newRouteCD.distanceMeters = Double(ttlDstc)
            } else {
                newRouteCD.distanceMeters = 0.0
            }
            for (index, mkr) in route.wayPoints.enumerated() {
                _ = WaypointCD.wayPointCDFrom(marker: mkr, inRouteCD: newRouteCD, withIndex: index, intoMoc: moc)
            }
            return newRouteCD
        } else {
            return nil
        }
    }

}
