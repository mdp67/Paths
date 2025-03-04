//
//  Waypoint.swift
//  Paths
//
//  Created by Mark Porcella on 12/11/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

//import UIKit
//import CoreLocation
//import MapKit
//import GoogleMaps
//import GooglePlaces
//import GoogleMapsDirections
//
//class WayPoint: Equatable {
//    
//    var coordinate: CLLocationCoordinate2D
//    var boolCalculatedRoute: Bool
//    var googleMarker: GMSMarker
//    var intWayPointLinkedTo: Int?
//    var titleLinkedSearchAnno: String?
//    var title: String? { didSet(newTitle) { googleMarker.title = newTitle } }
//    var foundRoute: GoogleMapsDirections.Response.Route?
//    var selectedRouteIndex: Int? = 0
//    var directPolyline: MKPolyline?
//    var directDistance: Double?
//    var steps: [StepAnnotation]?
//    
//    
//    var subtitle: String? // unused for protocol
//
//    init(cl2D: CLLocationCoordinate2D) {
//        self.coordinate = cl2D
//        self.boolCalculatedRoute = true
//        googleMarker = GMSMarker(position: cl2D)
//    }
//    
//    init(wptCD: WaypointCD) {
//        coordinate = CLLocationCoordinate2D(latitude: wptCD.latitude, longitude: wptCD.longitude)
//        boolCalculatedRoute = wptCD.isCalculated
//        selectedRouteIndex = Int(wptCD.foundRouteIndex)
//        if let linkWpt = wptCD.numWaypointLinkedTo { intWayPointLinkedTo = Int(linkWpt) }
//        googleMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: wptCD.latitude, longitude: wptCD.longitude))
//    }
//
//    init(linkedWpt: WayPoint, withIndex indexOfLinkedWpt:Int) {
//        
//        coordinate = linkedWpt.coordinate
//        boolCalculatedRoute = true
//        intWayPointLinkedTo = indexOfLinkedWpt
//        googleMarker = GMSMarker(position: linkedWpt.googleMarker.position)
//    }
//    
//    init(linkedSearchPt: MKPointAnnotation) {
//        
//        coordinate = linkedSearchPt.coordinate
//        boolCalculatedRoute = true
//        if let linkedTitle = linkedSearchPt.title { self.titleLinkedSearchAnno = linkedTitle }
//        googleMarker = GMSMarker(position: linkedSearchPt.coordinate)
//    }
//
//    static func ==(lhs: WayPoint, rhs: WayPoint) -> Bool {
//        return lhs.googleMarker == rhs.googleMarker
//    }
//}










