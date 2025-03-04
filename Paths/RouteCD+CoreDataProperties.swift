//
//  RouteCD+CoreDataProperties.swift
//  Paths
//
//  Created by Mark Porcella on 6/4/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import Foundation
import CoreData


extension RouteCD {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RouteCD> {
        return NSFetchRequest<RouteCD>(entityName: "RouteCD")
    }

    @NSManaged public var dateAccessed: NSDate?
    @NSManaged public var dateCreated: NSDate?
    @NSManaged public var distanceMeters: Double
    @NSManaged public var name: String?
    @NSManaged public var travelMode: Int16
    @NSManaged public var waypointsCD: NSSet?

}

// MARK: Generated accessors for waypointsCD
extension RouteCD {

    @objc(addWaypointsCDObject:)
    @NSManaged public func addToWaypointsCD(_ value: WaypointCD)

    @objc(removeWaypointsCDObject:)
    @NSManaged public func removeFromWaypointsCD(_ value: WaypointCD)

    @objc(addWaypointsCD:)
    @NSManaged public func addToWaypointsCD(_ values: NSSet)

    @objc(removeWaypointsCD:)
    @NSManaged public func removeFromWaypointsCD(_ values: NSSet)

}
