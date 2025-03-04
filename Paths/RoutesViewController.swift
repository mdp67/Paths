//
//  RoutesViewController.swift
//  Paths
//
//  Created by Mark Porcella on 6/1/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import UIKit
import CoreData
import MapKit

class RoutesViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, CLLocationManagerDelegate, NSFetchedResultsControllerDelegate, RouteTVCDelegate  {

    
    fileprivate struct Constants {
        static let editSegue = "editRouteFromUnwind"
        static let navigateSegue = "NavigateFromRoutes"
    }
    
    @IBOutlet weak var buttonSort: UIButton!
    fileprivate enum RouteSortOrder: String {
        case name = "name"
        case distance = "distanceMeters"
        case dateCreated = "dateCreated"
        case dateAccessed = "dateAccessed"
    }
    
    @IBOutlet weak var tableView: UITableView!  { didSet { tableView.delegate = self; tableView.dataSource = self } }
    fileprivate var fetchController: NSFetchedResultsController<RouteCD>?
    
    var moc: NSManagedObjectContext?
    var routes: NSSet?
    fileprivate var sortDescriptorString = RouteSortOrder.dateAccessed
    fileprivate var locManager = LocationManager.sharedInstance
    fileprivate var userLoc: CLLocationCoordinate2D?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updateUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        locManager.delegate = self
        locManager.startUpdatingLocation()
    }
    
    // MARK: -LocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse: locManager.startUpdatingLocation()
        case .denied: locManager.stopUpdatingLocation(); showAlertForLocationDenied()
        case .notDetermined, .restricted, .authorizedAlways: break
        }
        locManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let location = locations[0]
        guard location.horizontalAccuracy < 300 else { return }
        userLoc = location.coordinate
        if location.horizontalAccuracy < 10 { locManager.stopUpdatingLocation() }
        
    }
    
    fileprivate func updateUI() {
        guard let managedOC = moc else { fetchController = nil; return }
        createFetchResultController(managedOC)
    }
    
    @IBAction func createPath(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    fileprivate var boolSortAscending = false
    @IBAction func sort(_ sender: UIButton) {
        boolSortAscending = false
        switch sortDescriptorString {
        case RouteSortOrder.dateAccessed:
            sortDescriptorString = RouteSortOrder.distance
            buttonSort.setTitle("Sort: Distance", for: UIControlState())
        case RouteSortOrder.distance:
            sortDescriptorString = RouteSortOrder.name
            buttonSort.setTitle("Sort: Name", for: UIControlState())
            boolSortAscending = true
        case RouteSortOrder.name:
            sortDescriptorString = RouteSortOrder.dateCreated
            buttonSort.setTitle("Sort: 📅 Created", for: UIControlState())
        case RouteSortOrder.dateCreated:
            sortDescriptorString = RouteSortOrder.dateAccessed
            buttonSort.setTitle("Sort: 📅 Used", for: UIControlState())
        }
        updateUI()
    }
    
    fileprivate func createFetchResultController(_ managedOC: NSManagedObjectContext, withPredicate predicate: NSPredicate? = nil) {
        
        let fetchRequest = NSFetchRequest<RouteCD>(entityName: "RouteCD")
        print("raw value sort descriptor \(sortDescriptorString.rawValue)")
        if case .name = sortDescriptorString {
            fetchRequest.sortDescriptors =  [NSSortDescriptor(key: sortDescriptorString.rawValue, ascending: boolSortAscending, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        } else {
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: sortDescriptorString.rawValue, ascending: boolSortAscending)]
        }
        if let pred = predicate { fetchRequest.predicate = pred }
        fetchController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedOC, sectionNameKeyPath: nil, cacheName: nil)
        do {
            fetchController!.delegate = self
            try fetchController!.performFetch()
            tableView.reloadData()
        } catch {
            print("NSFetchedResultsController.performFetch() failed: \(error)")
        }
    }
    
    // Mark: TableViewDataSource
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "RouteCell", for: indexPath) as! RouteTableViewCell
        cell.indexPath = indexPath
        cell.delegate = self
        if let fetchRC = fetchController {
            let routeCD = fetchRC.object(at: indexPath)
            var name: String?
            var distanceString: String?
            var buttonTitle: String?
            
            routeCD.managedObjectContext?.performAndWait {
                name = routeCD.name
                if boolUseMetricUnitsDisplay {
                    distanceString = String(format: "%.2f km", routeCD.distanceMeters.km)
                } else {
                    distanceString = String(format: "%.2f mi.", routeCD.distanceMeters.mi)
                }
                
                switch routeCD.travelMode {
                case 0: buttonTitle = "Start 🚙 "
                case 1: buttonTitle = "Start 🚴🏼"
                case 2: buttonTitle = "Start 🚶"
                default: print("no travel mode saved")
                }
            }
            cell.buttonStart.setTitle(buttonTitle, for: UIControlState())
            cell.labelName.text = name
            cell.labelDistance.text = distanceString
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = fetchController?.sections , sections.count > 0 { return sections[section].numberOfObjects }
        print("returning 0")
        return 0
    }
    
    func numberOfSections(in tableView: UITableView) -> Int { return fetchController?.sections?.count ?? 1 }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    func deletePressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath) {
        if let fetchRC = fetchController {
            let routeCD = fetchRC.object(at: indexPath)
            let title = "Confirm Delete Path: \(routeCD.name!)?"
            let message = "There is no Undo."
            let confirmAC = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let confirm = UIAlertAction(title: "Confirm", style: .default) { (confirm) in
                routeCD.managedObjectContext?.delete(routeCD)
                self.saveUpdates()
                self.tableView.reloadData()
            }
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            confirmAC.addAction(confirm)
            confirmAC.addAction(cancel)
            present(confirmAC, animated: true, completion: nil)
        }
    }
    
    func editPressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath) {
        if let fetchContr = fetchController {
            let routeCD = fetchContr.object(at: indexPath)
            routeCD.setValue(Date(), forKey: "dateAccessed")
            saveUpdates()
            performSegue(withIdentifier: Constants.editSegue, sender: routeCD)
        }
    }
    func navPressedAt(RouteTVC tvc: RouteTableViewCell, atIndexPath indexPath: IndexPath) {
        if let fetchContr = fetchController {
            let routeCD = fetchContr.object(at: indexPath)
            routeCD.setValue(Date(), forKey: "dateAccessed")
            saveUpdates()
            let routeToNavigate = Route(routeCD: routeCD)
            var mkrsToNavigate = routeToNavigate.wayPoints
            if let usrLc = userLoc, let frstWpt = routeToNavigate.wayPoints.first {
                let distBetweenUserAndFirstWpt = CLLocation(locCord2D: usrLc).distance(from: CLLocation(locCord2D: frstWpt.position) )
                if distBetweenUserAndFirstWpt < 30 { mkrsToNavigate.remove(at: 0)  } // if user loc is same as first wpt, don't navigate to it
            }
            
            guard mkrsToNavigate.count > 0  else { showAlertForNotEnoughWpts(); return }
            guard let usrLoc = userLoc else { showAlertForLocationDenied(); return }
            
            if (UIApplication.shared.canOpenURL(NSURL(string:"https://maps.google.com")! as URL)) {
                var stringURL = "comgooglemapsurl://www.google.com/maps/dir/?api=1&origin="
                stringURL += "\(usrLoc.latitude),\(usrLoc.longitude)&"
                if let lastWpt =  mkrsToNavigate.last { stringURL += "destination=\(lastWpt.position.latitude),\(lastWpt.position.longitude)"}
                stringURL += "&travelmode=\(routeToNavigate.transitMode)"
                stringURL += "&dir_action=navigate"
                if mkrsToNavigate.count > 1 {
                    stringURL += "&waypoints="
                    mkrsToNavigate.dropLast().forEach { stringURL += "\($0.position.latitude),\($0.position.longitude)%7C" }
                }
                UIApplication.shared.open((NSURL(string: stringURL)! as URL), options: [:], completionHandler: nil)
            } else {
                NSLog("Can't use comgooglemaps://");
            }
            
        }
    }
    
    func showAlertForNotEnoughWpts() {
        let title = "Edit this route to add another Wpt"
        let unableAC = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        unableAC.addAction(acknowledgeAction)
        present(unableAC, animated: true, completion: nil)
        
    }
    
    func saveUpdates() {
        do { try self.moc?.save() }
        catch let error { print("Core Data Error: \(error)") }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if let segueId = segue.identifier {
            switch segueId {
            case Constants.editSegue:
                if let sendingRouteCD = sender as? RouteCD, let mapVC = segue.destination as? MapViewController  {
                    mapVC.routeCoreData = sendingRouteCD
                }
            default: print("trying to segue to unkown segue in RoutesVC")
                
            }
        }
    }
    
    fileprivate func showAlertForLocationDenied() {
        let title = "Paths Needs your location to navigate and configure the map"
        let message = "Please go to iPhone Settings App -> Paths -> Location -> While Using the App"
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let acknowledgeAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alert.addAction(acknowledgeAction)
        present(alert, animated: true, completion: nil)
    }
}






















