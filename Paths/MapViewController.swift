
//  ViewController.swift
//  Paths
//
//  Created by Mark Porcella on 11/25/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import UIKit
import MapKit
import GoogleMaps
import GooglePlaces
import GoogleMapsDirections
import CoreData
import Charts
import StoreKit

class MapViewController: UIViewController, CLLocationManagerDelegate, GMSMapViewDelegate, MKMapViewDelegate, RouteDelegate, UIDynamicAnimatorDelegate, UITextFieldDelegate, GMSAutocompleteViewControllerDelegate {

    fileprivate struct Constants {
        static let bottomMenuBoundary = "bottomMenuBoundary"
        static let savedRoutesSegue = "SavedRoutes"
        static let navigateSegue = "SavedRoutes"
    }
    
    var buttonPress: UIButton!
    var buttonGo: UIButton!
    var buttonMove: UIButton! { willSet { newValue.isHidden = true }}
    var buttonDelete: UIButton! { willSet { newValue.isHidden = true }}
    var blockDirectionsRequestForProxToWpt = false
    var alreadyShowSaveAC = false
    var routeCoreData: RouteCD?
    var persistentCont: NSPersistentContainer!
    var moc = (UIApplication.shared.delegate as? AppDelegate)?.persistentContainer.viewContext
    fileprivate var locManager = LocationManager.sharedInstance

    var route: Route! { didSet { if routeCoreData == nil { setTransitModeButtonBackground() } } }

    @IBOutlet var mapView: GMSMapView! {
        didSet {
            mapView.delegate = self
            if let selectedMapType = mapTypeDict[UserDefaults().integer(forKey: ConstantStrings.selectedMapType)] { mapView.mapType = selectedMapType }
        }
    }
    fileprivate weak var timer: Timer?
    fileprivate weak var timerPreviewRoute: Timer?
    fileprivate var mapRegionSet = false
    fileprivate var userLoc: CLLocationCoordinate2D?
    fileprivate var centeredMarker:GMSMarker? {
        willSet (cntrMkr) {
            if cntrMkr == nil {
                buttonPress.setImage(UIImage(named: "buttonDropPin"), for: UIControlState())
            } else if let cntMk = cntrMkr {
                if let lastRouteWpt = route.wayPoints.last, cntMk == lastRouteWpt { buttonPress.isHidden = true } // don't show button to drop new pin on last wpt
                else if cntMk.position != userLoc { buttonPress.setImage(UIImage(named: "buttonLinkPin")!, for: UIControlState()) }
                if mapViewApple != nil { mapViewApple!.centerCoordinate = cntMk.position } // for large scale map
            }
        }
    }
    fileprivate var searchMarker: GMSMarker?
    fileprivate var polylineGuide: GMSPolyline?
    fileprivate var rtPolyLineArrays: [[GMSPolyline]]?
    fileprivate var previewRtPolylines: [GMSPolyline]?
    fileprivate var routeWaypointStepMarkers: [[GMSMarker]]?
    fileprivate lazy var labelPreviewDistance: UILabel = {
        let labPrevDis = UILabel(frame: CGRect(x: 10, y: 10, width: 70, height: 70))
        labPrevDis.adjustsFontSizeToFitWidth = true
        labPrevDis.textColor = UIColor.red
        self.view.addSubview(labPrevDis)
        return labPrevDis
    }()
    
    fileprivate var mapViewMetersWidth: Double {
        let visibleRegion = mapView.projection.visibleRegion()
        return CLLocation(locCord2D: visibleRegion.nearLeft).distance(from: CLLocation(locCord2D: visibleRegion.farLeft))
    }
    fileprivate var boolChartRequestedHidden = true {
        willSet(hideElevationChart) {
            if hideElevationChart {
                removeAllElevationMarkers()
                showStepAnnotations()
                resetIconForPreviouslySelectedElMarker()
                viewChartCont.isHidden = true
            } else {
                addAllElevationMarkers()
                hideStepAnnotations()
                viewChartCont.isHidden = false
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateMap()
        addButtonsAndLabels()
        addMenu()
        locManager.requestWhenInUseAuthorization()
        route = Route(delegate: self)
        addViewsDependentOnRoute()
        checkForUsageAndRequestReview()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        locManager.delegate = self
        buttonDelete.isHidden = true
        buttonMove.isHidden = true
    }
    
    func returnMapCenter() -> CLLocationCoordinate2D { return CLLocationCoordinate2D(latitude: mapView.camera.target.latitude, longitude: mapView.camera.target.longitude) }
    
    func updateMap() {
        mapView.animate(toLocation: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129)) // in case user location not enabled show America!
        mapView.animate(toZoom: 3.0)
        mapView.isMyLocationEnabled = true
        if userLoc == nil { locManager.startUpdatingLocation() }
    }
    
    // MARK: -Target Action
    
    func onPress(_ sender: UIGestureRecognizer) {
        
        removeAllElevationMarkers()
        if route.wayPoints.count == 10 { showExcessWyptAlert() }
        route.placeWpt(atCLLocation2D: returnMapCenter())
        labelPreviewDistance.isHidden = true
        buttonPress.isHidden = true
        buttonMove.isHidden = false
        buttonDelete.isHidden = false
        removePolylineGuide()
        countButtonPressRegisteredDragToShowDirectionsAlert = 0
        removeSearchMarker()
    }
    
    func onMove(_sender: UIButton) {
        if let cntrMrkr = centeredMarker  { route.liftToMove(marker: cntrMrkr) } else { return }
        removeAllElevationMarkers()
        buttonPress.isHidden = false; buttonMove.isHidden = true; buttonDelete.isHidden = true
        removePreviewRoutePolyline()
        drawPolylineGuide()
    }
    
    func onDelete(_sender: UIButton) {
        guard let cntrMrkr = centeredMarker else { return }
        route.delete(marker: cntrMrkr)
        removeAllElevationMarkers()
        buttonPress.setImage(UIImage(named: "buttonDropPin"), for: UIControlState())
        buttonPress.isHidden = false; buttonMove.isHidden = true; buttonDelete.isHidden = true
        labelPreviewDistance.isHidden = true
        removePreviewRoutePolyline()
    }
    
    func onNavigate(_ sender: UIButton) {

        guard let usrLoc = userLoc else {
            locManager.startUpdatingLocation()
            showAlertForLocationDenied();
            return }
        
        var mkrsToNavigate = route.wayPoints
        if let frstWpt = route.wayPoints.first {
            let distBetweenUserAndFirstWpt = CLLocation(locCord2D: usrLoc).distance(from: CLLocation(locCord2D: frstWpt.position) )
            if distBetweenUserAndFirstWpt < 20 { mkrsToNavigate.remove(at: 0)  } // if user loc is same as first wpt, don't navigate to it
        }
        guard mkrsToNavigate.count > 0  else { showPromptToAddAnotherWpt(); return }
        
// THIS IS FOR SAVING PATH INFORMATION DURING NAVIGATION, NEED TO FIGURE OUT HOW TO HAVE GOOGLE GIVE CONTINUOUS TRAVEL
//        let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .short; dateFormatter.timeStyle = .short
//        var routeTitle = dateFormatter.string(from: Date())
//        if let rtCD = routeCoreData, let rtName = rtCD.name {
//            routeTitle = rtName
//        }
//        let title = "Paths will save your activity as \(routeTitle)."
//        let message = "To view speed, progress, and elevation change return to Paths while getting directions"
//        let navAlertCont = UIAlertController(title: title, message: message, preferredStyle: .alert)
//        let updateNameTitle = "Update Route Title And Navigate"
//        let updateNameAction = UIAlertAction(title: updateNameTitle, style: .default) { (updateTitle) in
//            
//        }
        
        
        
        
        if (UIApplication.shared.canOpenURL(NSURL(string:"https://maps.google.com")! as URL)) {

            var stringURL = "comgooglemapsurl://www.google.com/maps/dir/?api=1&origin="
            stringURL += "\(usrLoc.latitude),\(usrLoc.longitude)"
            if let lastWpt =  mkrsToNavigate.last { stringURL += "&destination=\(lastWpt.position.latitude),\(lastWpt.position.longitude)"}
//            stringURL += "&avoid=highways" // doesn't work
            stringURL += "&travelmode=\(route.transitMode)"
            if mkrsToNavigate.count > 1 {
                stringURL += "&waypoints="
                mkrsToNavigate.dropLast().forEach { stringURL += "via:\($0.position.latitude),\($0.position.longitude)%7C" }
            }
            
            print("directions request String: \(stringURL)")
            UIApplication.shared.open((NSURL(string: stringURL)! as URL), options: [:], completionHandler: nil)
        } else {
            NSLog("Can't use comgooglemaps://");
        }
    }
    
    func clearRoute() {
        mapView.clear()
        _ = routeWaypointStepMarkers?.flatMap {$0.forEach { $0.map = nil } }// the clear wasn't removing these...
        route.wayPoints.removeAll()
        labelPreviewDistance.isHidden = true
        labelTotalDistance.isHidden = true
        buttonElevation.isHidden = true
        buttonMove.isHidden = true
        buttonDelete.isHidden = true
        buttonPress.isHidden = false
        if boolChartRequestedHidden == false { closeChartResetElevationButton() }
    }
    
    func changeUnits(_ sender: UIButton) {
        boolUseMetricUnitsDisplay = !boolUseMetricUnitsDisplay
        UserDefaults().set(boolUseMetricUnitsDisplay, forKey: ConstantStrings.useMetricUnits)
        if boolUseMetricUnitsDisplay {
            sender.setTitle("🔄Units-Met", for: UIControlState())
        } else {
            sender.setTitle("🔄Units-Eng", for: UIControlState())
        }
        calculateElevationPointsIfRequestedAndPortrait() // show in the new units
        positionDistanceLabel() // changes the label, but changes the label to red
        if let rtTtlDstc = route.totalDistance {
            rtTtlDstc == 0 ? hideLabelDistanceAndButtonElevation() : showLabelDistanceAndButtonElevation()
            labelTotalDistance.text = "Dist: " + String(format: "%.1f", Double(rtTtlDstc).displayUnits) + stringDisplayForUnits
        }
    }
    
//    func addRtWptMarkers() { route.wayPoints.forEach { $0.map = mapView} } // was only using once
    
    // MARK: -LocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways: locManager.startUpdatingLocation()
        case .authorizedWhenInUse: locManager.startUpdatingLocation()
        case .denied: locManager.stopUpdatingLocation(); showAlertForLocationDenied()
        case .notDetermined, .restricted: break
        }
        locManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations[0]
        guard location.horizontalAccuracy < 3000 else { return }
        userLoc = location.coordinate
        if !mapRegionSet {
            mapRegionSet = true
            mapView.moveCamera(GMSCameraUpdate.setTarget(location.coordinate, zoom: 13))
        }
        if location.horizontalAccuracy < 10 { locManager.stopUpdatingLocation() }
    }
    
    // MARK: - Google Mapview Delegate Methods
    func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
        route.googlePrevRt = nil
        centeredMarker = nil
        movingMapFromLongPress ? (movingMapFromLongPress = false) : (buttonPress.isHidden = false)
        buttonDelete.isHidden = true
        buttonMove.isHidden = true
        hideWaypointEditButtons()
        startTimerMethodsTimer()
        removePreviewRoutePolyline()
        stopTimerToAddPreviewRoute()
        countButtonPressRegisteredDragToShowDirectionsAlert = 0
    }
    
    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        endTimerMethodsTimer()
        checkAndCenterWaypoint()
        if !blockDirectionsRequestForProxToWpt { startTimerToAddPreviewRoute() }
    }
    
    var movingMapFromLongPress = false
    func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
        guard mapViewApple == nil else { return } // position with precision looks like a long press
        route.placeWpt(atCLLocation2D: coordinate)
        movingMapFromLongPress = true
        buttonPress.isHidden = true
        buttonMove.isHidden = false
        buttonDelete.isHidden = false
        mapView.animate(toLocation: coordinate)
    }
    
    func onButtonCalculateElevations() {
        if boolChartRequestedHidden == false { // user wants chart hidden
            closeChartResetElevationButton()
        } else { // user wants chart visible
            boolChartRequestedHidden = false
            buttonElevation.setTitle("❌ Elevation", for: UIControlState())
            calculateElevationPointsIfRequestedAndPortrait()
        }
    }
    
    func closeChartResetElevationButton() { // also called from closeChartButton
        boolChartRequestedHidden = true
        buttonElevation.setTitle("⛰ Elevation", for: UIControlState())
    }
    
    // MARK: - Route Delegate Methods
    
    func displayRoute(_ route:Route) {
        removeAllRoutePolylines()
        removeAllStepMarkers()
        route.wayPoints.forEach { $0.map = mapView}
//        addRtWptMarkers() // the function was just the line of code above
        rtPolyLineArrays = [[GMSPolyline]]() // used to delete portions of rt polyline when user deletes wpts
        routeWaypointStepMarkers = [[GMSMarker]]()
        if let gogRt = route.googleRt {
            gogRt.legs.forEach { leg in
                var polyLinesForLeg = [GMSPolyline]()
                var stepsForLeg = [GMSMarker]()
                leg.steps.forEach { step in
                    
                    if let encodedString = step.polylinePoints, let path = GMSPath(fromEncodedPath: encodedString) {
                        let polyline = GMSPolyline(path: path)
                        polyline.zIndex = 2; polyline.geodesic = true; polyline.strokeWidth = 2; polyline.strokeColor = Color.blue;
                        polyLinesForLeg.append(polyline)
                        polyline.map = self.mapView;
                    }
                    // steps in route
                    if let start = step.startLocation, let stringDirections = step.htmlInstructions?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil) {
                        let markerForStep = GMSMarker(position: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude))
                        markerForStep.title = stringDirections
                        stepsForLeg.append(markerForStep)
                    }
                }
                rtPolyLineArrays?.append(polyLinesForLeg)
                routeWaypointStepMarkers?.append(stepsForLeg)
            }
            if boolChartRequestedHidden {
                _ = routeWaypointStepMarkers?.flatMap {$0.forEach { $0.map = mapView; $0.icon = UIImage(named: "annoDot"); $0.groundAnchor = CGPoint(x: 0.5, y: 0.5) } }
            }
            calculateElevationPointsIfRequestedAndPortrait()
        } else {
            print("There was no google route to add to map after removing previous polylines")
        }
    }
    
    func showStepAnnotations() { _ = routeWaypointStepMarkers?.flatMap {$0.forEach { $0.icon = UIImage(named: "annoDot"); $0.groundAnchor = CGPoint(x: 0.5, y: 0.5); $0.map = mapView } } }
    
    func hideStepAnnotations() { _ = routeWaypointStepMarkers?.flatMap {$0.forEach { $0.map = nil } } }
    
    func calculateElevationPointsIfRequestedAndPortrait() { if boolChartRequestedHidden == false && returnViewIsPortrait() { route.calculateElevations() } }
    
    func displayPreviewRoute(_ route:Route) {
        
        if let gogPrevRt = route.googlePrevRt {
            // check for user moving map prior to response from server
            guard let stringLatLong = gogPrevRt.summary, let locPreviewDestRequest = CLLocationCoordinate2D(fromLatLongString: stringLatLong), returnMapCenter() ~= locPreviewDestRequest else { return }
            removePolylineGuide()
            removePreviewRoutePolyline()
            previewRtPolylines = [GMSPolyline]()
            gogPrevRt.legs.forEach { $0.steps.forEach { // loop through every step and add it to map, and store them in array for easy removal
                if let encodedString = $0.polylinePoints, let path = GMSPath(fromEncodedPath: encodedString) {
                    let legPrevRtPolyline = GMSPolyline(path: path)
                    legPrevRtPolyline.spans = GMSStyleSpans(path, [GMSStrokeStyle.solidColor(.clear), GMSStrokeStyle.solidColor(.blue)], [50, 50], GMSLengthKind.geodesic)
                    previewRtPolylines?.append(legPrevRtPolyline)
                    legPrevRtPolyline.zIndex = 1; legPrevRtPolyline.geodesic = true; legPrevRtPolyline.strokeWidth = 2; legPrevRtPolyline.map = mapView
                }
                }   }
            if let lastLeg = gogPrevRt.legs.last {
                labelPreviewDistance.text = lastLeg.distance?.text
                labelPreviewDistance.textColor = UIColor.blue
            }
        }
    }
    
    func route(_ route:Route, addMarker:GMSMarker) {
        labelPreviewDistance.isHidden = true
        addMarker.map = mapView
        centeredMarker = addMarker
        updateAppleMapsWpts()
    }
    
    func route(_ route:Route, markerToRemove:GMSMarker) {
        markerToRemove.map = nil
        removePolylinesAndStepsFor(marker: markerToRemove)
        updateAppleMapsWpts()
    }
    
    func route(_ route:Route, markerMoving: GMSMarker) {
        markerMoving.map = nil
        removePolylinesAndStepsFor(marker: markerMoving)
        updateAppleMapsWpts()
    }
    
    func route(_ route:Route, errorFindingDirections:GoogleMapsService.StatusCode) {
        var title = ""
        switch errorFindingDirections {
        case .notFound: title = "At least one of the locations specified in the origin, destination, or waypoints could not be found"
        case .invalidRequest: title = "The provided request was invalid."
        case .overQueryLimit, .requestDenied: title = "Paths is having a problem talking to Google, please try again in a few min"
        case .maxWaypointsExceeded, .ok : return // already alerted the user when they selected more than 10 waypoints, it seems to work in the app even though Google says it shoudln't
        case .zeroResults: title = "Google couldn't find a route between the two points and the selected navigation mode. Try different navigation using the top left menu"
        case .unknownError: title = "Google is confused and can't find a route, please try different points"
        }
        let errorAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let ackAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        errorAC.addAction(ackAction)
        present(errorAC, animated: false) {
            if self.centeredMarker != nil {
                self.onDelete(_sender: self.buttonDelete)
            }
        }
    }
    func route(_ route:Route, errorStringFindingElevations:String) {
    
        var title = "There was an error finding the route elevations: "
        title += errorStringFindingElevations
        let errorAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let ackAction = UIAlertAction(title: "OK", style: .cancel) { (action) in
                self.activityIndicator.stopAnimating()
        }
        errorAC.addAction(ackAction)
        present(errorAC, animated: false, completion: nil)
    }
    
    func startingCalculationsForRoute(_ route:Route) { activityIndicator.startAnimating() }
    func endedCalcualtionsForRoute(_ route:Route) { activityIndicator.stopAnimating() }
    
    func route(_ route:Route, didUpdateTotalDistance totalDistance:Double) {
        totalDistance == 0.0 ? hideLabelDistanceAndButtonElevation() : showLabelDistanceAndButtonElevation()
        labelTotalDistance.text = "Dist: " + String(format: "%.1f", totalDistance.displayUnits) + stringDisplayForUnits
    }
    
    
    // MARK: - Elevation Calculations
    
    var elevationMarkers: [GMSMarker]?
    var selectedElMarker: GMSMarker?
    var highlightChrt: Highlight?
    fileprivate func selectClosestElevationMarkerIfInRange(ofCenterOrOptLocation optLoc: CLLocationCoordinate2D?) { // runs from the timer method, quickly
        
        if let elMkrs = elevationMarkers, let elMarkerAndDist = returnOptClosestMarkerAndDistance(fromCenterOrOptVal: optLoc, from: elMkrs), elMarkerAndDist.distance < (mapViewMetersWidth / 15), let selectedImage = UIImage(named: "highlightedElMrkr")  {
            resetIconForPreviouslySelectedElMarker()
            selectedElMarker = elMarkerAndDist.marker
            selectedElMarker!.icon = selectedImage
            if let slctdElMkrIndx = elevationMarkers?.index(of: selectedElMarker!), let elSlctdMkr = dictElIndexElevation?[slctdElMkrIndx] {
                
                let xIndexToHighlight = returnXIndexOfFurthestElMarkerInCaseOfRtOverlap(from: elMkrs, to: elMarkerAndDist.marker, atIndex: slctdElMkrIndx)
                var elevationOfElMrkr = Double(elSlctdMkr)
                if !boolUseMetricUnitsDisplay { elevationOfElMrkr = elevationOfElMrkr.ft  }
                highlightChrt = Highlight(x: Double(xIndexToHighlight), y: elevationOfElMrkr, dataSetIndex: 0)
                lineChart.highlightValue(highlightChrt)
            }
        }
    }
    
    func returnXIndexOfFurthestElMarkerInCaseOfRtOverlap(from elMkrs: [GMSMarker], to selectedMkr: GMSMarker, atIndex idx: Int) -> Int {
        var mkrsToCheck = elMkrs
        mkrsToCheck.remove(at: idx)
        if let closestMkrToSelectedMkr = returnOptClosestMarkerAndDistance(fromCenterOrOptVal: selectedMkr.position, from: mkrsToCheck) {
            if let indxClosestMrkr = mkrsToCheck.index(of: closestMkrToSelectedMkr.marker), indxClosestMrkr > idx {
                return returnXIndexOfFurthestElMarkerInCaseOfRtOverlap(from: mkrsToCheck, to: closestMkrToSelectedMkr.marker, atIndex: indxClosestMrkr)
            }
        }
        return idx
    }
    
    func resetIconForPreviouslySelectedElMarker() { if let slctdElMrkr = selectedElMarker, let elDot = UIImage(named: "elevationDot") { slctdElMrkr.icon = elDot } }
    
    var lineChart: LineChartView!  // need globaly to highlight
    var dictElIndexElevation: [Int : Double]? // need globaly to highlight
    func displayElevations(_ route:Route, elevationPts: [ElevationPoint], gain: Double, lost: Double, max: Double, min: Double) {

        guard returnViewIsPortrait() else { DispatchQueue.main.sync { activityIndicator.stopAnimating() }; return }
        if lineChart != nil { lineChart.removeFromSuperview() }  // get rid of the old chart
        lineChart = nil
        
        // Points that build the line chart
        var xVal = 0.0
        dictElIndexElevation = [Int : Double]() // used to get elevation value for waypoints
        var chartPts = [ChartDataEntry]()
        for elPt in elevationPts {
            if let elFromPt = elPt.elevation {
                dictElIndexElevation?[Int(xVal)] = elFromPt
                var elevationUnits: Double!
                boolUseMetricUnitsDisplay ? ( elevationUnits = elFromPt ) : ( elevationUnits = elFromPt.ft )
                chartPts.append(ChartDataEntry(x: xVal, y: elevationUnits))
                xVal += 1
            }
        }
        
        // Points that show user altitudes of waypoints
        var wptChartPoints: [ChartDataEntry]?
        if route.wayPoints.count > 2, let wptDistances = route.wptDistances, let totalRtDist = route.totalDistance {
            
            wptChartPoints = [ChartDataEntry]()
            var totalRtDistance = 0
            for wptDstnc in wptDistances {
                totalRtDistance += wptDstnc
                let indexElMkrClosestToWpt = Int((totalRtDistance * elevationPts.count) / totalRtDist)
                if var elevationForIndex = dictElIndexElevation?[indexElMkrClosestToWpt] {
                    if boolUseMetricUnitsDisplay == false { elevationForIndex = elevationForIndex.ft }
                    wptChartPoints!.append( ChartDataEntry(x: Double(indexElMkrClosestToWpt), y: elevationForIndex) )
                }
            }
            if var lastWptEl = elevationPts.last?.elevation, var firstWptEl = dictElIndexElevation?[0]  {
                if boolUseMetricUnitsDisplay == false { firstWptEl = firstWptEl.ft; lastWptEl = lastWptEl.ft }
                wptChartPoints!.insert(ChartDataEntry(x: 0.0, y: firstWptEl), at: 0)
                wptChartPoints!.append( ChartDataEntry(x: Double(elevationPts.count), y: lastWptEl) )
            }
        }

        // Build the line chart
        lineChart = LineChartView(frame: CGRect(x: 0, y: 0, width: viewChartCont.frame.width, height: viewChartCont.frame.height))
        var gainInSpecifiedUnits = Int(gain)
        var lossInSpecifiedUnits = Int(lost)
        if !boolUseMetricUnitsDisplay { gainInSpecifiedUnits = Int(gain.ft); lossInSpecifiedUnits = Int(lost.ft) }
        let dataSetForLine = LineChartDataSet(values: chartPts, label: "Total Gain: \(gainInSpecifiedUnits)\(stringDisplayForElevationUnits), Lost: \(lossInSpecifiedUnits)\(stringDisplayForElevationUnits)")
        dataSetForLine.setColor(NSUIColor.blue)
        dataSetForLine.drawCirclesEnabled = false
        dataSetForLine.drawValuesEnabled = false
        dataSetForLine.highlightEnabled = true
        dataSetForLine.highlightLineWidth = 1
        dataSetForLine.highlightColor = NSUIColor.red
        dataSetForLine.highlightLineDashLengths = [5, 5]
        
        var chartDataSets = [dataSetForLine]
        
        if let wptChrtPts = wptChartPoints {
            var dataSetForWpts: LineChartDataSet
            dataSetForWpts = LineChartDataSet(values: wptChrtPts, label: "Waypoints")
            dataSetForWpts.setCircleColor(NSUIColor.red)
            dataSetForWpts.setColor(NSUIColor.red)
            dataSetForWpts.circleHoleColor = NSUIColor.black
            dataSetForWpts.drawValuesEnabled = true
            dataSetForWpts.lineDashLengths = [1, 100000000]
            chartDataSets.append(dataSetForWpts)
        }
        
        let lineData = LineChartData(dataSets: chartDataSets)

        lineChart.chartDescription?.text = ""
        lineChart.rightAxis.drawAxisLineEnabled = false
        lineChart.rightAxis.drawLabelsEnabled = false
        lineChart.xAxis.drawGridLinesEnabled = false
        lineChart.xAxis.drawAxisLineEnabled = false
        lineChart.xAxis.drawLabelsEnabled = false
        self.viewChartCont.addSubview(self.lineChart)
        lineChart.data = lineData
        viewChartCont.bringSubview(toFront: buttonCloseChart)
        activityIndicator.stopAnimating()
        
        // Add elevation markers to mapview
        removeAllElevationMarkers()
        elevationMarkers = [GMSMarker]()
        for elPt in elevationPts {
            if let elLoc = elPt.location {
                let newMarker = GMSMarker(position: CLLocationCoordinate2D(latitude: elLoc.latitude, longitude: elLoc.longitude))
                elevationMarkers?.append(newMarker)
                newMarker.icon = UIImage(named: "elevationDot")!
                newMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                newMarker.isTappable = false
                newMarker.map = mapView
            }
        }
    }
    
    func removeAllElevationMarkers() { if let elMkrsOld = elevationMarkers { elMkrsOld.forEach { $0.map = nil } } }
    
    func addAllElevationMarkers() { if let mkrsToAdd = elevationMarkers { mkrsToAdd.forEach { $0.map = mapView } } }
    
    // MARK: - Timer Methods
    fileprivate func startTimerMethodsTimer() {
        DispatchQueue.main.async {
            guard self.timer == nil else { return }
            self.timer = Timer.scheduledTimer(timeInterval: 0.025, target: self, selector:#selector(self.timerMethods), userInfo: nil, repeats: true)
        }
    }
    
    fileprivate func endTimerMethodsTimer() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    func timerMethods() {
        drawPolylineGuide()
        positionDistanceLabel()
        selectClosestMarkerIfInRange()
        selectClosestElevationMarkerIfInRange(ofCenterOrOptLocation: nil)
        if mapViewApple != nil { updateAppleMap() }
    }

    fileprivate func drawPolylineGuide() {
        removePolylineGuide()
        let newPath = GMSMutablePath()
        if let mkrPsMvng = route.markerPosMoving {
            switch mkrPsMvng {
            case .onlyMarker: break
            case .firstOfMultiple:
                if let secondMarker = route.wayPoints[safe: 1] {
                    newPath.add(returnMapCenter())
                    newPath.add(secondMarker.position)
                }
            case .middleMarker(let indexMiddleMarker):
                if let markerPrior = route.wayPoints[safe: (UInt(indexMiddleMarker-1))], let markerAfter = route.wayPoints[safe: (UInt(indexMiddleMarker+1))] {
                    newPath.add(markerPrior.position)
                    newPath.add(returnMapCenter())
                    newPath.add(markerAfter.position)
                }
            case .lastMarker(let indexLastMarker):
                if let markerPrior = route.wayPoints[safe: (UInt(indexLastMarker-1))] {
                    newPath.add(markerPrior.position)
                    newPath.add(returnMapCenter())
                }
            }
        } else { // not moving
            guard let lastWpt = route.wayPoints.last, lastWpt.position != returnMapCenter() else { return }
            newPath.add(lastWpt.position)
            newPath.add(returnMapCenter())
        }
        polylineGuide = GMSPolyline(path: newPath)
        if let polyGd = polylineGuide {
            polyGd.spans = GMSStyleSpans(newPath, [GMSStrokeStyle.solidColor(.clear), GMSStrokeStyle.solidColor(.red)], [50, 50], GMSLengthKind.geodesic)
            polyGd.map = mapView
        }
    }
  
    fileprivate func positionDistanceLabel() {
        
        guard let lastWpt = route.wayPoints.last else { return }
        
        let distancePreviewPolyline = CLLocation(locCord2D: lastWpt.position).distance(from: CLLocation(locCord2D: returnMapCenter() ) )
        if polylineGuide != nil {
            labelPreviewDistance.text = String(format: "%.2f", distancePreviewPolyline.displayUnits ) + stringDisplayForUnits
            labelPreviewDistance.textColor = UIColor.red
        } else {
            labelPreviewDistance.textColor = UIColor.blue
        }
        
        var endPtOfLineFromViewCntr: CGPoint?
        if let mrkrPsMvng = route.markerPosMoving {
            switch mrkrPsMvng {
            case .middleMarker(let midMrkIndex): if let nextMkr = route.wayPoints[safe: (UInt(midMrkIndex + 1))] { endPtOfLineFromViewCntr = mapView.projection.point(for: nextMkr.position) }
            case .firstOfMultiple: if let secondWpt = route.wayPoints[safe: 1] { endPtOfLineFromViewCntr = mapView.projection.point(for: secondWpt.position) }
            case .lastMarker(let lastMrkIndex): if let scndToLastMkr = route.wayPoints[safe: (UInt(lastMrkIndex - 1))] { endPtOfLineFromViewCntr = mapView.projection.point(for: scndToLastMkr.position) }
            case .onlyMarker: return
            }
        } else { // not moving marker
            endPtOfLineFromViewCntr = mapView.projection.point(for: lastWpt.position)
        }
        guard let endPtLnFrmVwCntr = endPtOfLineFromViewCntr else { return }
        let mapCenter = mapView.projection.point(for: returnMapCenter())
        let halfwayPointBtwnMkrVwCntr = CGPoint(x: (endPtLnFrmVwCntr.x + mapCenter.x)/2, y: (endPtLnFrmVwCntr.y + mapCenter.y)/2)
        // find distance between in points between screen center and last wpt in points
        let difX = -mapCenter.x + endPtLnFrmVwCntr.x
        let difY = mapCenter.y - endPtLnFrmVwCntr.y
        let actualDistance = sqrt(difX * difX + difY * difY)
        // find max distance label is allowed to be from the map center
        let maxDistance = min(mapView.bounds.width/2.5, mapView.bounds.height/2.5)
        let minDistance = maxDistance * 0.3
        // determine label position based on screen distance between points
        if actualDistance < minDistance {
            labelPreviewDistance.isHidden = true
            return // don't calculate the distance
        } else if actualDistance < maxDistance {
            labelPreviewDistance.isHidden = false
            labelPreviewDistance.center = halfwayPointBtwnMkrVwCntr
        } else if actualDistance >= maxDistance {
            labelPreviewDistance.isHidden = false
            let xAddition = (maxDistance * difX / actualDistance) / 2
            let newX = mapCenter.x + xAddition
            let yAddition = (maxDistance * difY / actualDistance) / 2
            let newY = mapCenter.y - yAddition
            labelPreviewDistance.center = CGPoint(x: newX, y: newY)
        }
    }
    
    fileprivate func selectClosestMarkerIfInRange() {
        
        var allMkrs = route.wayPoints
        if boolChartRequestedHidden { if let stepsArrays = routeWaypointStepMarkers { allMkrs.append(contentsOf: stepsArrays.flatMap{ $0 }) } }
        if let srchMkr = searchMarker { allMkrs.append(srchMkr) }
        if let markerAndDist = returnOptClosestMarkerAndDistance(fromCenterOrOptVal: nil, from: allMkrs), markerAndDist.distance < (mapViewMetersWidth / 15)  {
            mapView.selectedMarker = markerAndDist.marker
        } else { mapView.selectedMarker = nil }
    }
    
    // MARK: - HelperMethods
    
    func removePolylinesAndStepsFor(marker: GMSMarker) {
        if let polylinesArrays = rtPolyLineArrays, let stepsArrays = routeWaypointStepMarkers, let mkrMovingPos = route.returnMarkerPostion(marker)  {
            switch mkrMovingPos {
            case .onlyMarker: break
            case .firstOfMultiple:
                if let firstPolylnsArray = polylinesArrays.first, let firstStepArray = stepsArrays.first {
                    firstPolylnsArray.forEach{ $0.map = nil }
                    firstStepArray.forEach{ $0.map = nil  }
                }
            case .middleMarker(let indexOfMarker):
                if let polylinesArrToNil = polylinesArrays[safe: (UInt(indexOfMarker-1))], let polylinesArrToNil2 = polylinesArrays[safe: (UInt(indexOfMarker))] {
                    polylinesArrToNil.forEach{ $0.map = nil}; polylinesArrToNil2.forEach{ $0.map = nil}
                }
                if let markersArrToNil = stepsArrays[safe: (UInt(indexOfMarker-1))], let markersArrToNil2 = stepsArrays[safe: (UInt(indexOfMarker))] {
                    markersArrToNil.forEach{ $0.map = nil }; markersArrToNil2.forEach{ $0.map = nil  }
                }
            case .lastMarker(_):
                if let lastPolylnsArray = polylinesArrays.last, let lastStepArray = stepsArrays.last {
                    lastPolylnsArray.forEach{ $0.map = nil}
                    lastStepArray.forEach{ $0.map = nil }
                }
            }
        }
    }
    
    func checkForUsageAndRequestReview() {
        if (UserDefaults().integer(forKey: ConstantStrings.numberTimesOpenedApp) % 20) == 0 {
            if #available(iOS 10.3, *) { SKStoreReviewController.requestReview() }
        }
    }
    
    fileprivate func removeAllRoutePolylines() { rtPolyLineArrays?.forEach{ $0.forEach { $0.map = nil } } }
    
    fileprivate func removeAllStepMarkers() { routeWaypointStepMarkers?.forEach{ $0.forEach{ $0.map = nil } } }
    
    fileprivate func hideWaypointEditButtons() { buttonMove.isHidden = true; buttonDelete.isHidden = true }
    
    fileprivate func showWaypointEditButtons() { buttonMove.isHidden = false; buttonDelete.isHidden = false }
    
    func hideLabelDistanceAndButtonElevation() { labelTotalDistance.isHidden = true; buttonElevation.isHidden = true }
    
    func showLabelDistanceAndButtonElevation() { labelTotalDistance.isHidden = false; if returnViewIsPortrait() { buttonElevation.isHidden = false } }
    
    fileprivate func startTimerToAddPreviewRoute() {
        timerPreviewRoute = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { [unowned self] (timer) in
            self.checkAndCenterWaypoint()
            if let lstWpt = self.route.wayPoints.last, let cntrdMkr = self.centeredMarker { guard lstWpt != cntrdMkr else { return } }
            self.route.calculatePREVIEWRouteAndDelegateDisplay(atMapCLLoc2D: self.returnMapCenter())
        })
    }
    
    fileprivate func showAlertForLocationDenied() {
        let title = "Paths Needs your location to navigate and configure the map"
        let message = "If you don't want to record your routes, please accept the next alert, If you want to record your route times, Please go to iPhone Settings App -> Paths -> Location -> Always"
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alert.addAction(acknowledgeAction)
        present(alert, animated: true, completion: nil)
    }
    
    var panAlertShown = false
    var countButtonPressRegisteredDragToShowDirectionsAlert = 0
    func showPanAlert() {
        countButtonPressRegisteredDragToShowDirectionsAlert += 1
        if (panAlertShown == false && countButtonPressRegisteredDragToShowDirectionsAlert == 15) {
            panAlertShown = true
            let title = "Please Move the Map, the Button is Stationary"
            let panAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
            panAC.addAction(acknowledgeAction)
            present(panAC, animated: true, completion: nil)
        }
    }
    
    fileprivate func stopTimerToAddPreviewRoute() { timerPreviewRoute?.invalidate(); timerPreviewRoute = nil }
    
    fileprivate func removePolylineGuide() { if let polyGd = polylineGuide { polyGd.map = nil; polylineGuide = nil } }
    
    fileprivate func removePreviewRoutePolyline() { if let prevRtPolylns = previewRtPolylines { prevRtPolylns.forEach { $0.map = nil } } }
    
    func removeSearchMarker() { searchMarker?.map = nil; searchMarker = nil }
    
    func changeTravelMode(sender: UIButton) {
        switch sender {
        case buttonAutoMode:
            UserDefaults().set(0, forKey: ConstantStrings.selectedNavType)
            route.transitMode = GoogleMapsDirections.TravelMode.driving
        case buttonCycleMode:
            UserDefaults().set(1, forKey: ConstantStrings.selectedNavType)
            route.transitMode = GoogleMapsDirections.TravelMode.bicycling
        case buttonWalkMode:
            UserDefaults().set(2, forKey: ConstantStrings.selectedNavType)
            route.transitMode = GoogleMapsDirections.TravelMode.walking
        default: break
        }
        setButtonNavigateTitle()
        removePreviewRoutePolyline()
        route.calculatePREVIEWRouteAndDelegateDisplay(atMapCLLoc2D: returnMapCenter())
        setTransitModeButtonBackground()
    }

    func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        if boolChartRequestedHidden == false  { selectClosestElevationMarkerIfInRange(ofCenterOrOptLocation: coordinate) }
    }
    
    fileprivate func returnOptClosestMarkerAndDistance(fromCenterOrOptVal startPosition: CLLocationCoordinate2D?, from markers: [GMSMarker]) -> (marker: GMSMarker, distance: Double)? {
        var strtPos: CLLocationCoordinate2D!
        if startPosition == nil {
            strtPos = returnMapCenter()
        } else {
            strtPos = startPosition
        }
        var distanceClosestMarker: Double?
        var closestMarker: GMSMarker?
        for marker in markers {
            let calcDistance = CLLocation(locCord2D: marker.position).distance(from: CLLocation(locCord2D: strtPos))
            if distanceClosestMarker == nil {
                distanceClosestMarker = calcDistance
                closestMarker = marker
            } else if let dstcClstMrkr = distanceClosestMarker, calcDistance < dstcClstMrkr {
                distanceClosestMarker = calcDistance
                closestMarker = marker
            }
        }
        if let marker = closestMarker, let distance = distanceClosestMarker { return (marker, distance) }
        return nil
    }
    
    fileprivate func checkAndCenterWaypoint()  {
        
        var waypointsToCenterOn = route.wayPoints
        if let usrLoc = userLoc { waypointsToCenterOn.append(GMSMarker(position: usrLoc)) } else { locManager.startUpdatingLocation() }
        if let srchMkr = searchMarker { waypointsToCenterOn.append(srchMkr) }
        if let (marker, distance) = returnOptClosestMarkerAndDistance(fromCenterOrOptVal: nil, from: waypointsToCenterOn) {
            blockDirectionsRequestForProxToWpt = false
            if distance < (mapViewMetersWidth / 1500){
                centeredMarker = marker
                guard let usrLoc = userLoc, usrLoc != marker.position, route.markerPosMoving == nil else { return }
                if let srchMkr = searchMarker, srchMkr == marker  { return } // don't show buttons for user loc or search marker
                showWaypointEditButtons()
            } else if distance < (mapViewMetersWidth / 15) {
                blockDirectionsRequestForProxToWpt = true
                guard route.markerPosMoving == nil else { return }
                mapView.animate(toLocation: marker.position)
            }
        }
    }
    
    // MARK: - Google Search
    func showSearchVC() {
        let acController = GMSAutocompleteViewController()
        acController.delegate = self
        present(acController, animated: true, completion: nil)
    }
    
    // Handle the user's selection.
    func viewController(_ viewController: GMSAutocompleteViewController, didAutocompleteWith place: GMSPlace) {
        mapView.moveCamera(GMSCameraUpdate.setTarget(place.coordinate))
        searchMarker = GMSMarker(position: place.coordinate)
        searchMarker?.map = mapView
        searchMarker?.icon = UIImage(named: "annoDot")
        searchMarker?.groundAnchor = CGPoint(x: 0.5, y: 0.5)
        searchMarker?.title = "\(place.name)"
        
        if let address = place.formattedAddress { searchMarker?.snippet = "\(address)" }
        mapView.selectedMarker = searchMarker
        dismiss(animated: true, completion: nil)
    }
    
    func viewController(_ viewController: GMSAutocompleteViewController, didFailAutocompleteWithError error: Error) {
        showAutocompleteErrorAC()
        dismiss(animated: true, completion: nil)
    }
    
    func wasCancelled(_ viewController: GMSAutocompleteViewController) {
        dismiss(animated: true, completion: nil)
    }
    // MARK: - Save Route
    
    func saveRoute() {
        if routeCoreData != nil {
            
            let title = "Replace Edited Path or Create New Path?"
            let replaceRouteAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            let replace = UIAlertAction(title: "Replace", style: .default){ [unowned self] (UIAlertAction) in
                self.deleteOldRouteCDAndCreateNew()
            }
            let new = UIAlertAction(title: "New", style: .default) { [unowned self] (UIAlertAction) in
                self.alertForNewRoute()
            }
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            replaceRouteAC.addAction(replace)
            replaceRouteAC.addAction(new)
            replaceRouteAC.addAction(cancel)
            present(replaceRouteAC, animated: true, completion: nil)
        } else {
            alertForNewRoute()
        }
        
    }
    
    fileprivate func alertForNewRoute() {
        
        let title = "Please name the Path"
        let saveTitleAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        saveTitleAC.addTextField{ (textfield) -> Void in
            textfield.placeholder = "Path Name"
            textfield.delegate = self
        }
        let saveAction = UIAlertAction(title: "Save", style: .default) { alert -> Void in
            if let firstTextField = saveTitleAC.textFields?.first, let textInField = firstTextField.text {
                self.route.name = textInField
            }
            self.moc?.perform() {
                _ = RouteCD.routeCDFromRoute(self.route, inMOC: self.moc!)
                do {
                    try self.moc?.save()
                    self.clearRoute()
                    self.performSegue(withIdentifier: Constants.savedRoutesSegue, sender: nil)
                } catch let error {
                    print("Core Data Error: \(error)")
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        saveTitleAC.addAction(saveAction)
        saveTitleAC.addAction(cancelAction)
        present(saveTitleAC, animated: true, completion: nil)
    }
    
    fileprivate func deleteOldRouteCDAndCreateNew() { // check the clear route
        
        if let moc = routeCoreData?.managedObjectContext {
            let dateCreated = routeCoreData!.dateCreated
            if let prevCreatedRouteCoreData = self.routeCoreData { moc.delete(prevCreatedRouteCoreData)}
            do {
                self.routeCoreData = nil
                _ = RouteCD.routeCDFromRoute(route, inMOC: moc, dateCreated: dateCreated! as Date)
                try moc.save()
                self.clearRoute()
                self.performSegue(withIdentifier: Constants.savedRoutesSegue, sender: nil)
            } catch let error {
                print("Core Data error: \(error)")
            }
        }
    }
    
    func showRoutes() { self.performSegue(withIdentifier: Constants.savedRoutesSegue, sender: nil) }
    
    func changeMapType() {
        if let selectedMapType = mapTypeDict[UserDefaults().integer(forKey: ConstantStrings.selectedMapType)] {
            switch selectedMapType {
            case GMSMapViewType.terrain:
                mapView.mapType = GMSMapViewType.hybrid
                UserDefaults().set(1, forKey: ConstantStrings.selectedMapType)
            case GMSMapViewType.hybrid:
                mapView.mapType = GMSMapViewType.normal
                UserDefaults().set(2, forKey: ConstantStrings.selectedMapType)
            case GMSMapViewType.normal:
                mapView.mapType = GMSMapViewType.terrain
                UserDefaults().set(0, forKey: ConstantStrings.selectedMapType)
            default: break
            }
        }
    }
    
    func showClearRouteAC() {
        let title = "Confirm Clear Route?"
        let clearAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { [unowned self] (action) in
            self.clearRoute()
        }
        let cancleAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        clearAC.addAction(cancleAction)
        clearAC.addAction(confirmAction)
        present(clearAC, animated: true, completion: nil)
    }
    
    func showPromptToAddAnotherWpt() {
        let title = "Please pan the map and press the \"Press\" button to add another waypoint"
        let unableAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        unableAC.addAction(acknowledgeAction)
        present(unableAC, animated: true, completion: nil)
    }
    
    
    func showExcessWyptAlert() {
        let title = "You can continue to build the path, but Google will only navigate to 9 intermediate points"
        let excessWptAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let ackowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        excessWptAC.addAction(ackowledgeAction)
        present(excessWptAC, animated: true, completion: nil)
    }
    
    func showAutocompleteErrorAC() {
        let title = "Google can't perform autocomplete, please check internet connection"
        let autoCpltAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        autoCpltAC.addAction(acknowledgeAction)
        present(autoCpltAC, animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let segueId = segue.identifier {
            switch segueId {
            case Constants.savedRoutesSegue: if let destinationVC = segue.destination as? RoutesViewController { destinationVC.moc = self.moc }
            default: print("no segue recognized")
            }
        }
    }
    
    var unwoundOnce = false
    override func viewWillDisappear(_ animated: Bool) {
        unwoundOnce = false
    }
    
    @IBAction func editRouteFromUnwind(_ segue: UIStoryboardSegue) {
        guard unwoundOnce == false else { return }
        unwoundOnce = true
        boolChartRequestedHidden = true
        if let routeCDToEdit = routeCoreData {
            clearRoute()
            route = Route(routeCD: routeCDToEdit)
            route.delegate = self
            for marker in route.wayPoints { marker.map = mapView }
            route.calculateRouteAndDelegateDisplay()
            zoomMapToAllMarkers()
        }
    }
    
    fileprivate func zoomMapToAllMarkers() {
        var bounds = GMSCoordinateBounds()
        route.wayPoints.forEach{ bounds = bounds.includingCoordinate($0.position) }
        mapView.moveCamera(GMSCameraUpdate.fit(bounds))
    }
    
    // limit length of Path Names
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let currentString = textField.text else { return true }
//        let newLength = currentString.count + string.count - range.length  SHOULD WORK, TRY IT
        let newLength = currentString.characters.count + string.characters.count - range.length
        return newLength < 60
    }
    
    // MARK: - Add Views + Buttons + Animations
    func addButtonsAndLabels() {
        addButtonPress()
        addActivityIndicator()
        addButtonMove()
        addButtonDelete()
        addLabelTotalDistance()
        addViewTravelMode()
        addButtonAutoMode()
        addButtonCycleMode()
        addButtonWalkMode()
        addButtonZoom()
        addButtonElevation()

    }
    
    func addViewsDependentOnRoute() {
        addButtonNavigate() // uses the route.transitMode to determine the button label
        addButtonSearch() // constrained to the button navigate on small phones
        addViewChartCont()
        addButtonCloseChart()
    }
    
    var activityIndicator: UIActivityIndicatorView!
    func addActivityIndicator() {
        activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        activityIndicator.color = .red
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        view.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0))
    }
    
    func addButtonPress() {
        buttonPress = UIButton(frame: CGRect(x: 0, y: 0, width: 42, height: 60))
        buttonPress.setImage(UIImage(named: "buttonDropPin"), for: UIControlState())
        buttonPress.translatesAutoresizingMaskIntoConstraints = false
        buttonPress.layer.cornerRadius = 5
        buttonPress.layer.borderColor = UIColor.black.cgColor
        buttonPress.layer.borderWidth = 0.5
        buttonPress.addTarget(self, action: #selector(onPress), for: .touchUpInside)
        buttonPress.addTarget(self, action: #selector(showPanAlert), for: .touchDragInside)
        view.addSubview(buttonPress)
        view.addConstraint(NSLayoutConstraint(item: buttonPress, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: buttonPress, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: -26))
        view.addConstraint(NSLayoutConstraint(item: buttonPress, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 42))
        view.addConstraint(NSLayoutConstraint(item: buttonPress, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 60))
    }
    
    func addButtonMove() {
        buttonMove = UIButton(frame: CGRect(x: 0, y: 0, width: 50, height: 60))
        buttonMove.setImage(UIImage(named: "buttonMoveAnnotation"), for: UIControlState())
        buttonMove.translatesAutoresizingMaskIntoConstraints = false
        buttonMove.layer.borderColor = UIColor.black.cgColor
        buttonMove.layer.borderWidth = 0.5
        buttonMove.layer.cornerRadius = 5
        buttonMove.addTarget(self, action: #selector(onMove), for: .touchUpInside)
        view.addSubview(buttonMove)
        view.addConstraint(NSLayoutConstraint(item: buttonMove, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50))
        view.addConstraint(NSLayoutConstraint(item: buttonMove, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 60))
        view.addConstraint(NSLayoutConstraint(item: buttonMove, attribute: .trailing, relatedBy: .equal, toItem: buttonPress, attribute: .centerX, multiplier: 1, constant: 0.5))
        view.addConstraint(NSLayoutConstraint(item: buttonMove, attribute: .top, relatedBy: .equal, toItem: buttonPress, attribute: .bottom, multiplier: 1, constant: -0.5))
    }
    
    func addButtonDelete() {
        buttonDelete = UIButton(frame: CGRect(x: 0, y: 0, width: 50, height: 60))
        buttonDelete.setImage(UIImage(named: "buttonDeleteAnnotation"), for: UIControlState())
        buttonDelete.translatesAutoresizingMaskIntoConstraints = false
        buttonDelete.layer.borderColor = UIColor.black.cgColor
        buttonDelete.layer.borderWidth = 0.5
        buttonDelete.layer.cornerRadius = 5
        buttonDelete.addTarget(self, action: #selector(onDelete), for: .touchUpInside)
        view.addSubview(buttonDelete)
        view.addConstraint(NSLayoutConstraint(item: buttonDelete, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50))
        view.addConstraint(NSLayoutConstraint(item: buttonDelete, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 60))
        view.addConstraint(NSLayoutConstraint(item: buttonDelete, attribute: .leading, relatedBy: .equal, toItem: buttonPress, attribute: .centerX, multiplier: 1, constant: -0.5))
        view.addConstraint(NSLayoutConstraint(item: buttonDelete, attribute: .top, relatedBy: .equal, toItem: buttonPress, attribute: .bottom, multiplier: 1, constant: -0.5))
    }
    
    var labelTotalDistance: UILabel! { didSet { labelTotalDistance.isHidden = true }}
    func addLabelTotalDistance() {
        labelTotalDistance = UILabel(frame: CGRect(x: 0, y: 0, width: 105, height: 30))
        labelTotalDistance.translatesAutoresizingMaskIntoConstraints = false
        labelTotalDistance.layer.cornerRadius = 5
        labelTotalDistance.textColor = UIColor.white
        labelTotalDistance.textAlignment = .center
        labelTotalDistance.adjustsFontSizeToFitWidth = true
        labelTotalDistance.layer.backgroundColor = UIColor.blue.cgColor
        labelTotalDistance.font = UIFont.systemFont(ofSize: 16)
        view.addSubview(labelTotalDistance)
        NSLayoutConstraint.activate([
            labelTotalDistance.safeTopAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            labelTotalDistance.safeLeftAnchor.constraint(equalTo: view.layoutMarginsGuide.leftAnchor)
            ])
//        view.addConstraint(NSLayoutConstraint(item: labelTotalDistance, attribute: .leading, relatedBy: .equal, toItem: view, attribute: .leading, multiplier: 1, constant: 5))
//        view.addConstraint(NSLayoutConstraint(item: labelTotalDistance, attribute: .top, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1, constant: 15))
        view.addConstraint(NSLayoutConstraint(item: labelTotalDistance, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: labelTotalDistance, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var viewTravelMode : UIView!
    func addViewTravelMode() {
        viewTravelMode = UIView(frame: CGRect.zero)
        viewTravelMode.translatesAutoresizingMaskIntoConstraints = false
        viewTravelMode.backgroundColor = UIColor.white
        viewTravelMode.layer.cornerRadius = 5
        viewTravelMode.layer.borderColor = UIColor.black.cgColor
        viewTravelMode.layer.borderWidth = 0.5
        viewTravelMode.clipsToBounds = true
        view.addSubview(viewTravelMode)
//        view.addConstraint(NSLayoutConstraint(item: viewTravelMode, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1, constant: -5))
//        view.addConstraint(NSLayoutConstraint(item: viewTravelMode, attribute: .top, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1, constant: 15))
        view.addConstraint(NSLayoutConstraint(item: viewTravelMode, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: viewTravelMode, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
        NSLayoutConstraint.activate([
            viewTravelMode.safeTopAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            viewTravelMode.safeRightAnchor.constraint(equalTo: view.layoutMarginsGuide.rightAnchor)
            ])
    }
    
    var buttonAutoMode : UIButton!
    func addButtonAutoMode() {
        buttonAutoMode = UIButton(frame: CGRect.zero)
        buttonAutoMode.translatesAutoresizingMaskIntoConstraints = false
        buttonAutoMode.backgroundColor = UIColor.white
        buttonAutoMode.setTitle("🚘", for: UIControlState())
        buttonAutoMode.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        buttonAutoMode.addTarget(self, action: #selector(changeTravelMode(sender:)), for: .touchUpInside)
        let borderLayer = CALayer()
        borderLayer.backgroundColor = UIColor.black.cgColor
        borderLayer.frame = CGRect(x: -0.5, y: 0, width: 0.5, height: 30)
        buttonAutoMode.layer.addSublayer(borderLayer)
        viewTravelMode.addSubview(buttonAutoMode)
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonAutoMode, attribute: .leading, relatedBy: .equal, toItem: viewTravelMode, attribute: .leading, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonAutoMode, attribute: .top, relatedBy: .equal, toItem: viewTravelMode, attribute: .top, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonAutoMode, attribute: .bottom, relatedBy: .equal, toItem: viewTravelMode, attribute: .bottom, multiplier: 1, constant: 0))
    }
    
    var buttonCycleMode : UIButton!
    func addButtonCycleMode() {
        buttonCycleMode = UIButton(frame: CGRect.zero)
        buttonCycleMode.translatesAutoresizingMaskIntoConstraints = false
        buttonCycleMode.backgroundColor = UIColor.white
        buttonCycleMode.setTitle("🚲", for: UIControlState())
        buttonCycleMode.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        buttonCycleMode.addTarget(self, action: #selector(changeTravelMode(sender:)), for: .touchUpInside)
        let borderLayer = CALayer()
        borderLayer.backgroundColor = UIColor.black.cgColor
        borderLayer.frame = CGRect(x: buttonCycleMode.frame.width - 0.5, y: 0, width: 0.5, height: 30)
        buttonCycleMode.layer.addSublayer(borderLayer)
        viewTravelMode.addSubview(buttonCycleMode)
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonCycleMode, attribute: .top, relatedBy: .equal, toItem: viewTravelMode, attribute: .top, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonCycleMode, attribute: .bottom, relatedBy: .equal, toItem: viewTravelMode, attribute: .bottom, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonCycleMode, attribute: .leading, relatedBy: .equal, toItem: buttonAutoMode, attribute: .trailing, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonCycleMode, attribute: .width, relatedBy: .equal, toItem: buttonAutoMode, attribute: .width, multiplier: 1, constant: 0))
    }
    
    var buttonWalkMode: UIButton!
    func addButtonWalkMode() {
        buttonWalkMode = UIButton(frame: CGRect.zero)
        buttonWalkMode.translatesAutoresizingMaskIntoConstraints = false
        buttonWalkMode.backgroundColor = UIColor.white
        buttonWalkMode.setTitle("🚶", for: UIControlState())
        buttonWalkMode.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        buttonWalkMode.addTarget(self, action: #selector(changeTravelMode(sender:)), for: .touchUpInside)
        let borderLayer = CALayer()
        borderLayer.backgroundColor = UIColor.black.cgColor
        borderLayer.frame = CGRect(x: buttonWalkMode.frame.width - 0.5, y: 0, width: 0.5, height: 30)
        buttonWalkMode.layer.addSublayer(borderLayer)
        viewTravelMode.addSubview(buttonWalkMode)
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonWalkMode, attribute: .leading, relatedBy: .equal, toItem: buttonCycleMode, attribute: .trailing, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonWalkMode, attribute: .trailing, relatedBy: .equal, toItem: viewTravelMode, attribute: .trailing, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonWalkMode, attribute: .top, relatedBy: .equal, toItem: viewTravelMode, attribute: .top, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonWalkMode, attribute: .bottom, relatedBy: .equal, toItem: viewTravelMode, attribute: .bottom, multiplier: 1, constant: 0))
        viewTravelMode.addConstraint(NSLayoutConstraint(item: buttonWalkMode, attribute: .width, relatedBy: .equal, toItem: buttonCycleMode, attribute: .width, multiplier: 1, constant: 0))
    }
    
    func setTransitModeButtonBackground() {
        switch route.transitMode {
        case .driving:
            buttonAutoMode.backgroundColor = ColorConstants.LightGreen
            buttonCycleMode.backgroundColor = UIColor.white
            buttonWalkMode.backgroundColor = UIColor.white
        case .bicycling:
            buttonAutoMode.backgroundColor = UIColor.white
            buttonCycleMode.backgroundColor = ColorConstants.LightGreen
            buttonWalkMode.backgroundColor = UIColor.white
        case .walking:
            buttonAutoMode.backgroundColor = UIColor.white
            buttonCycleMode.backgroundColor = UIColor.white
            buttonWalkMode.backgroundColor = ColorConstants.LightGreen
        default: break
        }
    }
    
    var viewChartCont: UIView!
    func addViewChartCont() {
        viewChartCont = UIView(frame: CGRect.zero)
        viewChartCont.translatesAutoresizingMaskIntoConstraints = false
        viewChartCont.isHidden = true
        viewChartCont.layer.cornerRadius = 10
        viewChartCont.backgroundColor = UIColor.white
        viewChartCont.layer.borderColor = UIColor.black.cgColor
        viewChartCont.layer.borderWidth = 0.5
        viewChartCont.clipsToBounds = false
        view.addSubview(viewChartCont)
        view.bringSubview(toFront: viewMenuCont) // show it infront of the chart
        view.addConstraint(NSLayoutConstraint(item: viewChartCont, attribute: .leading, relatedBy: .equal, toItem: view, attribute: .leading, multiplier: 1, constant: 5))
        view.addConstraint(NSLayoutConstraint(item: viewChartCont, attribute: .trailing, relatedBy: .equal, toItem: view, attribute: .trailing, multiplier: 1, constant: -5))
        view.addConstraint(NSLayoutConstraint(item: viewChartCont, attribute: .top, relatedBy: .equal, toItem: buttonMove, attribute: .bottom, multiplier: 1, constant: 10))
        view.addConstraint(NSLayoutConstraint(item: viewChartCont, attribute: .bottom, relatedBy: .equal, toItem: buttonNavigate, attribute: .top, multiplier: 1, constant: -10))
    }
    
    var buttonCloseChart: UIButton!
    func addButtonCloseChart() {
        buttonCloseChart = UIButton(frame: CGRect.zero)
        buttonCloseChart.translatesAutoresizingMaskIntoConstraints = false
        buttonCloseChart.addTarget(self, action: #selector(closeChartResetElevationButton), for: .touchUpInside)
        if let closeCircle = UIImage(named: "closeCircle") { buttonCloseChart.setImage(closeCircle, for: UIControlState()) }
        buttonCloseChart.imageView?.contentMode = .scaleAspectFill
        buttonCloseChart.backgroundColor = .clear
        viewChartCont.addSubview(buttonCloseChart)
        viewChartCont.addConstraint(NSLayoutConstraint(item: buttonCloseChart, attribute: .trailing, relatedBy: .equal, toItem: viewChartCont, attribute: .trailing, multiplier: 1, constant: -5))
        viewChartCont.addConstraint(NSLayoutConstraint(item: buttonCloseChart, attribute: .top, relatedBy: .equal, toItem: viewChartCont, attribute: .top, multiplier: 1, constant: 5))
        viewChartCont.addConstraint(NSLayoutConstraint(item: buttonCloseChart, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40))
        viewChartCont.addConstraint(NSLayoutConstraint(item: buttonCloseChart, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40))
    }
    
    var buttonZoom: MenuButton!
    func addButtonZoom() {
        buttonZoom = MenuButton()
        buttonZoom.addTarget(self, action: #selector(showZoomedMap), for: .touchUpInside)
        buttonZoom.setTitle("🔍 Magnify", for: UIControlState())
        view.addSubview(buttonZoom)
        view.addConstraint(NSLayoutConstraint(item: buttonZoom, attribute: .top, relatedBy: .equal, toItem: viewTravelMode, attribute: .bottom, multiplier: 1, constant: 5))
        view.addConstraint(NSLayoutConstraint(item: buttonZoom, attribute: .trailing, relatedBy: .equal, toItem: viewTravelMode, attribute: .trailing, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: buttonZoom, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: buttonZoom, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var mapViewApple: MKMapView? {
        didSet { if mapViewApple != nil { mapViewApple!.delegate = self; mapViewApple!.showsUserLocation = false; mapViewApple!.mapType = MKMapType.satellite } }
    }
    
    func showZoomedMap() {
        print("Zoom pressed")
        if mapViewApple != nil {
            mapViewApple?.removeFromSuperview()
            mapViewApple = nil
            buttonZoom.setTitle("🔍 Magnify", for: UIControlState())
            return
        }
        buttonZoom.setTitle("🔍 Hide ❌", for: UIControlState())
        mapViewApple = MKMapView()
        mapViewApple?.translatesAutoresizingMaskIntoConstraints = false
        mapViewApple?.isMultipleTouchEnabled = false
        mapViewApple?.showsUserLocation = true
        let quarterWidth = view.frame.width * 0.4
        mapViewApple?.layer.cornerRadius = quarterWidth / 2
        
        updateAppleMapsWpts()
        view.addSubview(mapViewApple!)
        view.bringSubview(toFront: buttonPress)
        view.bringSubview(toFront: buttonMove)
        view.bringSubview(toFront: buttonDelete)
        updateAppleMap()
        view.addConstraint(NSLayoutConstraint(item: mapViewApple!, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: mapViewApple!, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0))
        view.addConstraint(NSLayoutConstraint(item: mapViewApple!, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .width, multiplier: 1, constant: quarterWidth))
        view.addConstraint(NSLayoutConstraint(item: mapViewApple!, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1, constant: quarterWidth))
    }

    func updateAppleMap() {
        let visibleRegion = mapView.projection.visibleRegion()
        let gogMapCLDegreesWide = abs(visibleRegion.nearLeft.latitude - visibleRegion.farLeft.latitude)
        let appleSpan = MKCoordinateSpan(latitudeDelta: gogMapCLDegreesWide / 50, longitudeDelta: gogMapCLDegreesWide / 50)
        
        let appleRegion = MKCoordinateRegion(center: returnMapCenter(), span: appleSpan)
        mapViewApple?.setRegion(appleRegion, animated: false)
    }
    
    var appleMapsAnnotations: [MKPointAnnotation]?
    func updateAppleMapsWpts() {
        guard mapViewApple != nil else { return }
        if let apleMpsAnnos = appleMapsAnnotations { mapViewApple?.removeAnnotations(apleMpsAnnos) }
        appleMapsAnnotations = [MKPointAnnotation]()
        route.wayPoints.forEach { (wpt) in
            if wpt.map == nil { return } // if the waypoint is moving
            let wptAnno = MKPointAnnotation()
            wptAnno.coordinate = wpt.position
            appleMapsAnnotations!.append(wptAnno)
            mapViewApple?.addAnnotation(wptAnno)
        }
    }
    
    var buttonNavigate: MenuButton!
    func addButtonNavigate() {
        buttonNavigate = MenuButton()
        setButtonNavigateTitle()
        buttonNavigate.addTarget(self, action: #selector(onNavigate(_:)), for: .touchUpInside)
        view.addSubview(buttonNavigate)
        view.addConstraint(NSLayoutConstraint(item: buttonNavigate, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: buttonNavigate, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
        NSLayoutConstraint.activate([
                buttonNavigate.safeRightAnchor.constraint(equalTo: view.layoutMarginsGuide.rightAnchor),
                buttonNavigate.safeBottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
            ])
    }
    
    var buttonElevation: MenuButton! { didSet { buttonElevation.isHidden = true }}
    func addButtonElevation() {
        buttonElevation = MenuButton()
        buttonElevation.addTarget(self, action: #selector(onButtonCalculateElevations), for: .touchUpInside)
        buttonElevation.setTitle("⛰ Elevation", for: UIControlState())
        view.addSubview(buttonElevation)
        view.addConstraint(NSLayoutConstraint(item: buttonElevation, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: buttonElevation, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
        var minWidth = view.frame.width
        if view.frame.height < view.frame.width { minWidth = view.frame.height }
        if minWidth < 374 {
            view.addConstraint(NSLayoutConstraint(item: buttonElevation, attribute: .top, relatedBy: .equal, toItem: viewTravelMode, attribute: .bottom, multiplier: 1, constant: 5))
            view.addConstraint(NSLayoutConstraint(item: buttonElevation, attribute: .centerX, relatedBy: .equal, toItem: viewTravelMode, attribute: .centerX, multiplier: 1, constant: 0))
        } else {
            NSLayoutConstraint.activate([ buttonElevation.safeTopAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor) ])
            view.addConstraint(NSLayoutConstraint(item: buttonElevation, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        }
        
    }
    
    var buttonSearch : UIButton!
    func addButtonSearch() {
        buttonSearch = MenuButton()
        buttonSearch.setTitle("Search", for: UIControlState())
        buttonSearch.addTarget(self, action: #selector(showSearchVC), for: .touchUpInside)
        view.addSubview(buttonSearch)
        var minWidth = view.frame.width
        if view.frame.height < view.frame.width { minWidth = view.frame.height }
        view.addConstraint(NSLayoutConstraint(item: buttonSearch, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: buttonSearch, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
        if minWidth < 374 {
            view.addConstraint(NSLayoutConstraint(item: buttonSearch, attribute: .bottom, relatedBy: .equal, toItem: buttonNavigate, attribute: .top, multiplier: 1, constant: -5))
            view.addConstraint(NSLayoutConstraint(item: buttonSearch, attribute: .centerX, relatedBy: .equal, toItem: buttonNavigate, attribute: .centerX, multiplier: 1, constant: 0))
        } else {
            NSLayoutConstraint.activate([ buttonSearch.safeBottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor) ])
            view.addConstraint(NSLayoutConstraint(item: buttonSearch, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        }
    }
    
    func setButtonNavigateTitle() {
        switch route.transitMode {
        case .driving: buttonNavigate.setTitle("🚘 Navigate", for: UIControlState())
        case .bicycling: buttonNavigate.setTitle("🚲 Navigate", for: UIControlState())
        case .walking: buttonNavigate.setTitle("🚶 Navigate" , for: UIControlState())
        default: break
        }
    }
    
    func addMenu() {
        addMenuContainer()
        addButtonMenu()
        addButtonSave()
        addButtonRoutes()
        addButtonClear()
        addButtonMapType()
        addButtonUnits()
    }
    
    var constraintMenuContBottom: NSLayoutConstraint!
    var viewMenuCont: UIView!
    func addMenuContainer() {
        viewMenuCont = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 205))
        viewMenuCont.translatesAutoresizingMaskIntoConstraints = false
        viewMenuCont.backgroundColor = UIColor.clear
        view.addSubview(viewMenuCont)
        view.addConstraint(NSLayoutConstraint(item: viewMenuCont, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 105))
        view.addConstraint(NSLayoutConstraint(item: viewMenuCont, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 205))
//        view.addConstraint(NSLayoutConstraint(item: viewMenuCont, attribute: .leading, relatedBy: .equal, toItem: view, attribute: .leading, multiplier: 1, constant: 5))
        
        constraintMenuContBottom = viewMenuCont.safeTopAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -30)
        NSLayoutConstraint.activate([
            viewMenuCont.safeLeftAnchor.constraint(equalTo: view.layoutMarginsGuide.leftAnchor),
            constraintMenuContBottom
            ])
    }
    
    var buttonMenu: MenuButton!
    func addButtonMenu() {
        buttonMenu = MenuButton()
        buttonMenu.setTitle("Menu ⬆︎", for: UIControlState())
        buttonMenu.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        viewMenuCont.addSubview(buttonMenu)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMenu, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMenu, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMenu, attribute: .top, relatedBy: .equal, toItem: viewMenuCont, attribute: .top, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMenu, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var buttonSave: MenuButton!
    func addButtonSave() {
        buttonSave = MenuButton()
        buttonSave.isHidden = true
        buttonSave.setTitle("💾 Save", for: UIControlState())
        buttonSave.addTarget(self, action: #selector(saveRoute), for: .touchUpInside)
        viewMenuCont.addSubview(buttonSave)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonSave, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonSave, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonSave, attribute: .top, relatedBy: .equal, toItem: buttonMenu, attribute: .bottom, multiplier: 1, constant: 5))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonSave, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var buttonRoutes: MenuButton!
    func addButtonRoutes()  {
        buttonRoutes = MenuButton()
        buttonRoutes.setTitle("📂  Routes", for: UIControlState())
        buttonRoutes.addTarget(self, action: #selector(showRoutes), for: .touchUpInside)
        viewMenuCont.addSubview(buttonRoutes)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonRoutes, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonRoutes, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonRoutes, attribute: .top, relatedBy: .equal, toItem: buttonSave, attribute: .bottom, multiplier: 1, constant: 5))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonRoutes, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var buttonClear: MenuButton!
    func addButtonClear() {
        buttonClear = MenuButton()
        buttonClear.setTitle("❌ Clear Rt", for: UIControlState())
        buttonClear.addTarget(self, action: #selector(showClearRouteAC), for: .touchUpInside)
        viewMenuCont.addSubview(buttonClear)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonClear, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonClear, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonClear, attribute: .top, relatedBy: .equal, toItem: buttonRoutes, attribute: .bottom, multiplier: 1, constant: 5))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonClear, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var buttonMapType: MenuButton!
    func addButtonMapType() {
        buttonMapType = MenuButton()
        buttonMapType.setTitle("🔄Map Type", for: UIControlState())
        buttonMapType.addTarget(self, action: #selector(changeMapType), for: .touchUpInside)
        viewMenuCont.addSubview(buttonMapType)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMapType, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMapType, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMapType, attribute: .top, relatedBy: .equal, toItem: buttonClear, attribute: .bottom, multiplier: 1, constant: 5))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonMapType, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    var buttonUnits: MenuButton!
    func addButtonUnits() {
        buttonUnits = MenuButton()
        UserDefaults().bool(forKey: ConstantStrings.useMetricUnits) ? buttonUnits.setTitle("🔄Units-Met", for: UIControlState()) : buttonUnits.setTitle("🔄Units-Eng", for: UIControlState())
        buttonUnits.addTarget(self, action: #selector(changeUnits), for: .touchUpInside)
        viewMenuCont.addSubview(buttonUnits)
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonUnits, attribute: .leading, relatedBy: .equal, toItem: viewMenuCont, attribute: .leading, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonUnits, attribute: .trailing, relatedBy: .equal, toItem: viewMenuCont, attribute: .trailing, multiplier: 1, constant: 0))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonUnits, attribute: .top, relatedBy: .equal, toItem: buttonMapType, attribute: .bottom, multiplier: 1, constant: 5))
        viewMenuCont.addConstraint(NSLayoutConstraint(item: buttonUnits, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 30))
    }
    
    // MARK: - Animation Vars and Functions
    
    fileprivate var layingOutSubviews = false
    override func viewWillLayoutSubviews() {
        layingOutSubviews = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layingOutSubviews = false
        positionDistanceLabel()
        updateMenuCollisionBottomPath()
        updateMenuSnapBehavior()
        showChartPortraitHideForLandscape()
    }
    
    var lastLayoutWasPortrait = true
    fileprivate func showChartPortraitHideForLandscape() {
        if lastLayoutWasPortrait && returnViewIsPortrait() { return } // laying out subview still in portrait
        
        if let totDis = route.totalDistance, totDis > 0 && returnViewIsPortrait() {
            buttonElevation.isHidden = false
            lastLayoutWasPortrait = true
            if boolChartRequestedHidden == false {
                viewChartCont.isHidden = false
                calculateElevationPointsIfRequestedAndPortrait()
            }
        }
        if lastLayoutWasPortrait == false  { // rotated to portrait
            
        } else if lastLayoutWasPortrait == true && returnViewIsPortrait() == false { // rotated to landscape
            lastLayoutWasPortrait = false
            buttonElevation.isHidden = true
            viewChartCont.isHidden = true // hides the chart, without switching the boolChartRequestedHidden var
            
        }
    }

    fileprivate func returnViewIsPortrait () -> Bool { if view.frame.height > view.frame.width { return true } else { return false } }
    
    fileprivate var menuHidden = true
    func showMenu()  {
        if menuHidden == true {
            menuAnimator.addBehavior(menuSnapBehavior)
            buttonSave.isHidden = false
        } else if menuHidden == false {
            menuCollider.addBoundary(withIdentifier: Constants.bottomMenuBoundary as NSCopying, for: collisionMenuBottomPath)
            menuAnimator.addBehavior(menuCollider)
            menuAnimator.addBehavior(menuGravity)
        }
        menuHidden = !menuHidden
    }
    
    fileprivate lazy var menuAnimator: UIDynamicAnimator = { [unowned self] in
        let lazyAnimator = UIDynamicAnimator(referenceView: self.view)
        lazyAnimator.delegate = self
        return lazyAnimator
        }()
    
    fileprivate lazy var menuGravity: UIGravityBehavior = { [unowned self] in
        let lazyGravity = UIGravityBehavior()
        lazyGravity.angle = CGFloat(Double.pi / 2)
        lazyGravity.magnitude = 1.0
        lazyGravity.addItem(self.viewMenuCont)
        return lazyGravity
        }()
    
    fileprivate lazy var menuCollider: UICollisionBehavior = { [unowned self] in
        let lazyCollisionBehavior = UICollisionBehavior()
        lazyCollisionBehavior.addItem(self.viewMenuCont)
        return lazyCollisionBehavior
        }()
    
    func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
        
        if animator == menuAnimator {
            menuAnimator.removeAllBehaviors()
            if menuHidden == true {
                constraintMenuContBottom.constant = -30
                buttonSave.isHidden = true
                buttonMenu.setTitle("Menu ⬆︎", for: UIControlState())
            } else if menuHidden == false {
                constraintMenuContBottom.constant = -205
                buttonMenu.setTitle("Hide ⬇︎", for: UIControlState())
            }
        }
    }
    
    fileprivate var collisionMenuBottomPath: UIBezierPath!
    fileprivate func updateMenuCollisionBottomPath() {
        let bottomMenuY = view.frame.height + viewMenuCont.frame.height - view.safeBottomPadding - 29
        collisionMenuBottomPath = UIBezierPath(rect: CGRect(x: 0, y: bottomMenuY, width: view.frame.width, height: 1))
    }
    
    fileprivate var menuSnapBehavior: UISnapBehavior!
    fileprivate func updateMenuSnapBehavior() {
        let coordX = viewMenuCont.frame.midX
        let coordY = view.frame.height - viewMenuCont.frame.height / 2 - view.safeBottomPadding
        menuSnapBehavior = UISnapBehavior(item: viewMenuCont, snapTo: CGPoint(x: coordX, y: coordY))
    }
    



    
    

    
    
    
    
    
    
}











