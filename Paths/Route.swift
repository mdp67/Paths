//
//  Route.swift
//  Paths
//
//  Created by Mark Porcella on 12/11/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import Foundation
import GoogleMaps
import GooglePlaces
import GoogleMapsDirections
import MapKit
import CoreData
import Polyline


protocol RouteDelegate: class {
    
    var route:Route! {get set}
    func route(_ route:Route, markerMoving:GMSMarker)
    func route(_ route:Route, markerToRemove:GMSMarker)
    func route(_ route:Route, errorFindingDirections:GoogleMapsService.StatusCode)
    func route(_ route:Route, errorStringFindingElevations:String)
    func route(_ route:Route, addMarker:GMSMarker)
    func startingCalculationsForRoute(_ route:Route)
    func endedCalcualtionsForRoute(_ route:Route)
    func route(_ route:Route, didUpdateTotalDistance totalDistance:Double)
    func displayRoute(_ route:Route)
    func displayPreviewRoute(_ route:Route)
    func displayElevations(_ route:Route, elevationPts: [ElevationPoint], gain: Double, lost: Double, max: Double, min: Double)
}


enum markerPosition {
    case onlyMarker
    case firstOfMultiple
    case middleMarker(Int)
    case lastMarker(Int)
}

struct PolylineName {
    static let altPolyline = "altPolyLine"
    static let userPolyline = "userRoute"
    static let previewPolyline = "previewPolyline"
    static let guideline = "guideline"
}

class Route: NSObject, ElevationCalculator {
    
    struct Constants {
        static let userWptTitle = "userWpt"
        static let straightPolyLineSub = "straightPolyLineSubtitle"
    }
    var googleRt: GoogleMapsDirections.Response.Route?
    var googlePrevRt: GoogleMapsDirections.Response.Route?
    var avoidHighways = false
    var wayPoints = [GMSMarker]()
    var markerPosMoving: markerPosition?
    var previewMiddleGMSLocCord2D: [GoogleMapsService.LocationCoordinate2D]?
    var previewStartGMS: GoogleMapsService.LocationCoordinate2D?
    var previewDestGMS: GoogleMapsService.LocationCoordinate2D?
    var transitMode: GoogleMapsDirections.TravelMode { didSet { if wayPoints.count > 1 {  calculateRouteAndDelegateDisplay() } } }
    var boolBlockAddingPolyLine = false
    weak var delegate: RouteDelegate?
    var dateCreated: Date?
    var name: String?
    var previewRoutesData: (startClLoc2d: CLLocationCoordinate2D, endClLoc2d: CLLocationCoordinate2D, travelType: Int, calculatedRoutes: [MKRoute])?
    var totalDistance: Int? { return googleRt?.legs.flatMap{$0.steps}.flatMap{$0.distance?.value}.reduce(0,+) }
    var lastElevationRequestString: String?
    var previousElevationRequestURL: URL?
    var wptDistances: [Int]?
    
    init(delegate: RouteDelegate) { self.delegate = delegate; self.transitMode = selectedNavType }
    
    init(routeCD: RouteCD) {
        if let transitType = travelTypeDict[Int(routeCD.travelMode)] {
            self.transitMode = transitType
        } else {
            self.transitMode = selectedNavType
        }
        name = routeCD.name
        var sortedWptCDs = [WaypointCD]()
        if let unsortedWptCDs = routeCD.waypointsCD?.allObjects as? [WaypointCD] {
            sortedWptCDs = unsortedWptCDs.sorted { $0.indexRoute < $1.indexRoute }
            for wptCD in sortedWptCDs { wayPoints.append(GMSMarker(position: CLLocationCoordinate2D(latitude: wptCD.latitude, longitude: wptCD.longitude))) }
        }
    }
    
    func placeWpt(atCLLocation2D mapCoord: CLLocationCoordinate2D)  {
        let newMarker = GMSMarker(position: mapCoord)
        newMarker.appearAnimation = GMSMarkerAnimation.pop
        if let mkrPsMvg = markerPosMoving {
            switch mkrPsMvg {
            case .onlyMarker, .firstOfMultiple: wayPoints[0] = newMarker
            case .middleMarker(let index), .lastMarker(let index): wayPoints[index] = newMarker;
            }
            markerPosMoving = nil
        } else { // not moving a waypoint
            self.wayPoints.append(newMarker)
        }
        delegate?.route(self, addMarker: newMarker)
        if wayPoints.count > 1 { calculateRouteAndDelegateDisplay() }
    }
    
    func calculateRouteAndDelegateDisplay() {
        guard (wayPoints.count > 1), let lastWpt = wayPoints.last, let firstWpt = wayPoints.first else { print("Trying to build route with < 2 points"); return }
        let originGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: firstWpt.position)
        let destinationGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: lastWpt.position)
        let middleGMSLocCord2D = wayPoints.dropFirst().dropLast().map { GoogleMapsService.LocationCoordinate2D(CLLoc2D: $0.position) }
        if let prvStrtGMS = previewStartGMS, let prvDstGMS = previewDestGMS, let prvwMddlGMSLcCrd2d = previewMiddleGMSLocCord2D, let gglePrvRt = googlePrevRt {
            if prvStrtGMS == originGMS, prvDstGMS == destinationGMS, prvwMddlGMSLcCrd2d == middleGMSLocCord2D { // the route was previously calculated for the preview, use it
                googleRt = gglePrvRt
                print("using the route preview")
                delegate?.displayRoute(self)
                markerPosMoving = nil
                if let ttlDstc = self.totalDistance { self.delegate?.route(self, didUpdateTotalDistance: Double(ttlDstc))}
                return
            }
        }
        self.delegate?.startingCalculationsForRoute(self)
        GoogleMapsDirections.direction(fromOriginCoordinate: originGMS,
                                       toDestinationCoordinate: destinationGMS,
                                       travelMode: self.transitMode,
                                       wayPoints: middleGMSLocCord2D.map { GoogleMapsService.Place.coordinate(coordinate: $0) },
                                       alternatives: false,
                                       avoid: avoidHighways ? [GoogleMapsDirections.RouteRestriction.highways] : nil,
//                                       avoid: [GoogleMapsDirections.RouteRestriction.highways], // this works, but not in the transfer to Google Maps, update in later releases to allow route restrictions
                                       language: nil,
                                       units: boolUseMetricUnitsDisplay ?  GoogleMapsDirections.Unit.metric : GoogleMapsDirections.Unit.imperial,
                                       region: nil,
                                       arrivalTime: nil,
                                       departureTime: Date.init(),
                                       trafficModel: (self.transitMode == .driving) ?  GoogleMapsDirections.TrafficMode.bestGuess : nil,
                                       transitMode: nil,
                                       transitRoutingPreference: nil,
                                       completion: { [unowned self] (optResponse, optError) in
                                        
                                        self.delegate?.endedCalcualtionsForRoute(self)
                                        if let response = optResponse, let responseStatus = response.status {
                                            switch responseStatus {
                                            case .ok, .maxWaypointsExceeded:
                                                self.googlePrevRt = nil
                                                self.previewMiddleGMSLocCord2D = nil
                                                self.previewDestGMS = nil
                                                self.previewStartGMS = nil
                                                self.googleRt = response.routes.first
                                                self.findwptDistances()
                                                self.delegate?.displayRoute(self)
                                                if let ttlDstc = self.totalDistance { self.delegate?.route(self, didUpdateTotalDistance: Double(ttlDstc))}
                                            default: self.delegate?.route(self, errorFindingDirections: responseStatus)
                                            }
                                        }
        })
    }
    
    
    func calculatePREVIEWRouteAndDelegateDisplay(atMapCLLoc2D mapCLLoc2d: CLLocationCoordinate2D) {
        guard let firstWpt = wayPoints.first, wayPoints.count > 0 else { return }
        previewMiddleGMSLocCord2D = wayPoints.dropFirst().dropLast().map { GoogleMapsService.LocationCoordinate2D(CLLoc2D: $0.position) }
        if let mkrPsMv = markerPosMoving {
            switch mkrPsMv {
            case .onlyMarker: break
            case .firstOfMultiple:
                previewStartGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: mapCLLoc2d)
                if let lastWpt = wayPoints.last { previewDestGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: lastWpt.position) } else { break }
            case .middleMarker(let indexOfMovingMkr):
                previewStartGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: firstWpt.position)
                if let lastWpt = wayPoints.last { previewDestGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: lastWpt.position) } else { break }
                if let prvwMddleGMS = previewMiddleGMSLocCord2D, let _ = prvwMddleGMS[safe: (UInt(indexOfMovingMkr-1))] { // safety check
                    previewMiddleGMSLocCord2D![indexOfMovingMkr-1] = GoogleMapsService.LocationCoordinate2D(CLLoc2D: mapCLLoc2d) // replace the middle loc with the map center location
                }
            case .lastMarker(_):
                previewStartGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: firstWpt.position)
                previewDestGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: mapCLLoc2d)
            }
        } else { // Not moving a wpt
            previewStartGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: firstWpt.position)
            previewDestGMS = GoogleMapsService.LocationCoordinate2D(CLLoc2D: mapCLLoc2d)
            if let lastWpt = wayPoints.last, wayPoints.count > 1 { // add the last wpt as a middle point, need to route through it
                if previewMiddleGMSLocCord2D != nil { previewMiddleGMSLocCord2D!.append(GoogleMapsService.LocationCoordinate2D(CLLoc2D: lastWpt.position)) }
            }
        }
        var middleWptPlaces = Array<GoogleMapsService.Place>()
        if previewMiddleGMSLocCord2D != nil { middleWptPlaces = previewMiddleGMSLocCord2D!.map{ GoogleMapsService.Place.coordinate(coordinate: $0) } }
        if let prvStrtGMS = previewStartGMS, let prvDstGMS = previewDestGMS {
            GoogleMapsDirections.direction(fromOriginCoordinate: prvStrtGMS,
                                           toDestinationCoordinate: prvDstGMS,
                                           travelMode: self.transitMode,
                                           wayPoints: middleWptPlaces,
                                           alternatives: false,
                                           avoid: avoidHighways ? [GoogleMapsDirections.RouteRestriction.highways] : nil,
                                           language: nil,
                                           units: boolUseMetricUnitsDisplay ?  GoogleMapsDirections.Unit.metric : GoogleMapsDirections.Unit.imperial,
                                           region: nil,
                                           arrivalTime: nil,
                                           departureTime: Date.init(),
                                           trafficModel: (self.transitMode == .driving) ?  GoogleMapsDirections.TrafficMode.bestGuess : nil,
                                           transitMode: nil,
                                           transitRoutingPreference: nil,
                                           completion: { [unowned self] (optResponse, optError) in
                                            
                                            if let response = optResponse, response.status == GoogleMapsDirections.StatusCode.ok {
                                                self.googlePrevRt = response.routes.first
                                                self.googlePrevRt?.summary = "\(mapCLLoc2d.latitude)- \(mapCLLoc2d.longitude)" // to compare with center point on delegate
                                                self.delegate?.displayPreviewRoute(self)
                                            } else if let error = optError {
                                                debugPrint("the error finding the route instructions was \(error)")
                                            }
            })
        }

        
    }
    
    func liftToMove(marker: GMSMarker) {
        markerPosMoving = returnMarkerPostion(marker)
        delegate?.route(self, markerMoving: marker)
    }
    
    func delete(marker: GMSMarker) {
        delegate?.route(self, markerToRemove: marker)
        if let indexWpt = wayPoints.index(of: marker) { wayPoints.remove(at: indexWpt) }
        calculateRouteAndDelegateDisplay()
    }
    
    func returnMarkerPostion(_ wpt: GMSMarker) -> markerPosition? {
        if wayPoints.count == 1, let firstWpt = wayPoints.first, firstWpt == wpt {
            return .onlyMarker
        } else {
            if let wptIndex = wayPoints.index(of: wpt) {
                switch wptIndex {
                case 0: return .firstOfMultiple
                case (wayPoints.count - 1): return .lastMarker(wayPoints.count - 1)
                default: return .middleMarker(wayPoints.index(of: wpt)!)
                }
            } else {
                return nil
            }
        }
    }
    
    func startCalculatingElevations() {
        delegate?.startingCalculationsForRoute(self)
    }
    
    func errorFindingElevations(errorString: String) {
        delegate?.route(self, errorStringFindingElevations: errorString)
    }
    
    func completedElevation(with elevationPts: [ElevationPoint], gain: Double, lost: Double, max: Double, min: Double, url: URL) {
        previousElevationRequestURL = url
        delegate?.displayElevations(self, elevationPts: elevationPts, gain: gain, lost: lost, max: max, min: min)
    }
    
    fileprivate func findwptDistances() {
        if wayPoints.count > 1, let rtLegs = googleRt?.legs {
            wptDistances = [Int]()
            for rtLeg in rtLegs {
                if let distance = rtLeg.distance?.value {
                    wptDistances!.append(distance)
                }
            }
        }
    }
    
    
    
  
}





fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

























//    func calculateElevations(for markers: [[GMSMarker]]?) {
//
//
//        //
//        //        guard let stpMkrsArrays = markers else { return }
//        //        let stpMkrs = stpMkrsArrays.flatMap{ $0 }
//        //        var urlString = "https://maps.googleapis.com/maps/api/elevation/json?path="
//        //        for (index, stpMkr) in stpMkrs.enumerated() {
//        //            urlString += "\(stpMkr.position.latitude)"
//        //            urlString += ","
//        //            urlString += "\(stpMkr.position.longitude)"
//        //            if index == (stpMkrs.endIndex - 1) { continue }
//        //            urlString += "%7C"
//        //        }
//
//
//        var urlString = "https://maps.googleapis.com/maps/api/elevation/json?path=enc:"
//        if let gglRt = self.googleRt {
//
//            var coordinatesForCombinedPath = [CLLocationCoordinate2D]()
//            gglRt.legs.forEach{ $0.steps.forEach { if let plylnpts = $0.polylinePoints {
//                print("polyline points encoded string \(plylnpts)")
//                if let gmsPath = GMSPath(fromEncodedPath: plylnpts) {
//                    for i in 0..<(gmsPath.count() - 1) {
//                        let coord = gmsPath.coordinate(at: i)
//                        coordinatesForCombinedPath.append(coord)
//                        print("coordinate for path: \(coord)")
//                    }
//                }
//
//
//                } }  }
//            let polyline = Polyline(coordinates: coordinatesForCombinedPath)
//            let encodedPolyline: String = polyline.encodedPolyline
//            print("encoded polyline: \(encodedPolyline)")
//            urlString += encodedPolyline
//        }
//
//
//
//
//        urlString += "&samples="
//        urlString += returnSringCalcNumElevationSamples()
//        urlString += "&key=AIzaSyA4GaeHp8Tl6OlCJ-B8fZ1A4Nx5cZyFCa4"
//        print("URL String \(urlString)")
////        let escapedAddress = address.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
//        let escapedURLString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
//        let error = NSError(domain: "Error Building Google Request URL", code: 0, userInfo: nil)
//        guard let urlGog = URL(string: escapedURLString!)  else { delegate?.route(self, errorFindingElevations: error); return }
//        print("URL created by method elevation \(urlGog) end URL created")
//        delegate?.startingCalculationsForRoute(self)
//
//
//        let urlRequest = URLRequest(url: urlGog)
//        let config = URLSessionConfiguration.default
//        let session = URLSession(configuration: config)
//        let task = session.dataTask(with: urlRequest) { [unowned self] (optData, optResponse, optError) in
//
////            if let error = optError as NSError? { self.delegate?.route(self, errorFindingElevations: error)  }
//            if let data = optData {
//                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
//                    if let dict = json as? [String : Any] {
//                        if let arrayOfDict = dict["results"] as? [[String: Any]] {
//                            self.elevations = [Double]()
//                            for locDict in arrayOfDict {
//                                if let elevation = locDict["elevation"] as? Double {
//                                    self.elevations?.append(elevation)
//                                }
//                            }
//                            self.lastElevationRequestString = urlString
//                            let metrics = self.returnMetricsForElevations(elevations: self.elevations!)
//                            self.delegate?.displayElevations(self, gain: metrics.gain, lost: metrics.lost, max: metrics.max, min: metrics.min)
//                        }
//                    }
//                }
//            }
//        }
//        task.resume()
//    }







//
