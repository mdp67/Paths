//
//  LocationManager.swift
//  Paths
//
//  Created by Mark Porcella on 11/27/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import Foundation

import UIKit
import CoreLocation

class LocationManager: NSObject {
    
    static let sharedInstance: CLLocationManager = {
        let instance = CLLocationManager()
        instance.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        instance.distanceFilter = kCLDistanceFilterNone
        instance.pausesLocationUpdatesAutomatically = true
        instance.activityType = CLActivityType.fitness
        instance.allowsBackgroundLocationUpdates = true
        return instance
    }()
}
