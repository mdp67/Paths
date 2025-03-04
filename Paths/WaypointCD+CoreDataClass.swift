//
//  WaypointCD+CoreDataClass.swift
//  Paths
//
//  Created by Mark Porcella on 12/11/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import Foundation
import CoreData
import GoogleMaps

@objc(WaypointCD)

public class WaypointCD: NSManagedObject {
    
    class func wayPointCDFrom(marker: GMSMarker, inRouteCD routeCD: RouteCD, withIndex index: Int, intoMoc moc: NSManagedObjectContext) -> WaypointCD? {
        if let newWaypointCD = NSEntityDescription.insertNewObject(forEntityName: "WaypointCD", into: moc) as? WaypointCD {
            
            newWaypointCD.routeCD = routeCD
            newWaypointCD.indexRoute = Int16(index)
            newWaypointCD.latitude = marker.position.latitude
            newWaypointCD.longitude = marker.position.longitude
            return newWaypointCD
        } else { return nil }
    }

}
