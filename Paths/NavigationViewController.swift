//
//  NavigationViewController.swift
//  Paths
//
//  Created by Mark Porcella on 6/13/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import UIKit
import MapKit
import GoogleMaps
import GooglePlaces
import GoogleMapsDirections
import CoreData

class NavigationViewController: UIViewController, GMSMapViewDelegate {

//    @IBOutlet var mapView: GMSMapView! {
//        didSet {
//            mapView.delegate = self
//            if let selectedMapType = mapTypeDict[UserDefaults().integer(forKey: ConstantStrings.selectedMapType)] { mapView.mapType = selectedMapType }
//            mapView.isMyLocationEnabled = true
//        }
//    }
//    fileprivate var locManager = LocationManager.sharedInstance
//    fileprivate var userLoc: CLLocationCoordinate2D?
//    var route: Route!
//    var tupleLegStepsMarkers: [(leg: GoogleMapsDirections.Response.Route.Leg, polylines: Array<GMSPolyline>, steps: Array<GMSMarker>)] = []
//    var currentLeg: GoogleMapsDirections.Response.Route.Leg?
//    var currentPolylineArr: [GMSPolyline]?
//    var currentPolyline: GMSPolyline?
//    var currentStepArr: [GMSMarker]?
//    var currentStep: GMSMarker?
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        showAllMarkers()
//        displayRoute(self.route)
//        for marker in route.wayPoints { marker.map = mapView }
//        locManager.startUpdatingLocation()
//    }
//
//    fileprivate func showAllMarkers() {
//        
//        var bounds = GMSCoordinateBounds()
//        route.wayPoints.forEach{ bounds = bounds.includingCoordinate($0.position) }
//        mapView.moveCamera(GMSCameraUpdate.fit(bounds))
//    }
//    
//    func displayRoute(_ route:Route) {
//        if let gogRt = route.googleRt {
//            gogRt.legs.forEach { leg in
//                print("leg \(String(describing: leg.distance))")
//                var polyLinesForLeg = Array<GMSPolyline>()
//                var stepsForLeg = Array<GMSMarker>()
//                leg.steps.forEach { step in
//                    if let encodedString = step.polylinePoints, let path = GMSPath(fromEncodedPath: encodedString) {
//                        let polyline = GMSPolyline(path: path)
//                        polyLinesForLeg.append(polyline)
//                        polyline.zIndex = 2; polyline.geodesic = true; polyline.strokeWidth = 2; polyline.strokeColor = Color.blue;
//                        polyline.map = self.mapView;
//                    }
//                    if let start = step.startLocation, let stringDirections = step.htmlInstructions?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil) {
//                        let markerForStep = GMSMarker(position: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
//                        markerForStep.title = stringDirections
//                        markerForStep.map = mapView
//                        markerForStep.icon = UIImage(named: "annoDot")
//                        stepsForLeg.append(markerForStep)
//                        
//                    }
//                }
//                tupleLegStepsMarkers.append((leg, polyLinesForLeg, stepsForLeg))
//            }
//        } else {
//            print("There was no google route to add to map after removing previous polylines")
//        }
//        if let firstTpLgStpsMrkrs = tupleLegStepsMarkers.first {
//            currentLeg = firstTpLgStpsMrkrs.leg
//            currentStepArr = firstTpLgStpsMrkrs.steps
//            if let firstStp = currentStepArr?.first { currentStep = firstStp }
//            currentPolylineArr = firstTpLgStpsMrkrs.polylines
//            if let firstPlln = currentPolylineArr?.first { currentPolyline = firstPlln }
//        }
//    }
//    
//    // MARK: -LocationManagerDelegate
//    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//        switch status {
//        case .authorizedWhenInUse: locManager.startUpdatingLocation()
//        case .denied: locManager.stopUpdatingLocation(); showAlertForLocationDenied()
//        case .notDetermined, .restricted, .authorizedAlways: break
//        }
//        locManager.startUpdatingLocation()
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//    
//        print("updated location")
//        let location = locations[0]
//        guard location.horizontalAccuracy < 300 else { return }
//        userLoc = location.coordinate
//        print("updated location better than 300")
//        mapView.animate(toLocation: CLLocationCoordinate2D(CLLoc: location))
//    }
//    
//    
//    
//    
//    
//    
//    
//    
//    fileprivate func showAlertForLocationDenied() {
//        let title = "Paths Needs your location to navigate and configure the map"
//        let message = "Please go to iPhone Settings App -> Paths -> Location -> While Using the App"
//        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
//        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
//        alert.addAction(acknowledgeAction)
//        present(alert, animated: true, completion: nil)
//    }
//    
//    func displayStepsForRoute(_ route: Route) { }
//    func route(_ route:Route, markerMoving:GMSMarker) {}
//    func route(_ route:Route, markerToRemove:GMSMarker) {}
//    func route(_ route:Route, errorFindingDirections:NSError) {}
//    func route(_ route:Route, addMarker:GMSMarker) {}
//    func startingCalculationsForRoute(_ route:Route) {}
//    func endedCalcualtionsForRoute(_ route:Route) {}
//    func route(_ route:Route, didUpdateTotalDistance totalDistance:Double) {}
//    func displayPreviewRoute(_ route:Route) {}
//    func displayElevations(_ route:Route ) {}
//
//    
    
    
    
    
    
    
    
    
    
    

}
