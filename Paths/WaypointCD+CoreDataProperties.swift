//
//  WaypointCD+CoreDataProperties.swift
//  Paths
//
//  Created by Mark Porcella on 5/31/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import Foundation
import CoreData


extension WaypointCD {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WaypointCD> {
        return NSFetchRequest<WaypointCD>(entityName: "WaypointCD")
    }

    @NSManaged public var indexRoute: Int16
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var routeCD: RouteCD?

}
