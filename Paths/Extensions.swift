//
//  Extensions.swift
//  Paths
//
//  Created by Mark Porcella on 11/27/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import Foundation
import CoreLocation
import GoogleMaps
import GooglePlaces
import GoogleMapsDirections

extension CLLocationCoordinate2D: Equatable { }
public func ==(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    if lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude { return true }
    return false
}

public func ~=(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    if lhs.latitude.roundTo(places: 2) == rhs.latitude.roundTo(places: 2), lhs.longitude.roundTo(places: 2) == rhs.longitude.roundTo(places: 2) { return true }
    return false
}

public extension CLLocationCoordinate2D {
    
    init?(fromLatLongString latLongString: String) {
        let latLong = latLongString.components(separatedBy: "- ")
        if let latStr = latLong.first, let longStr = latLong.last, let latDouble: CLLocationDegrees = Double("\(latStr)"), let LongDouble: CLLocationDegrees = Double("\(longStr)") {
            self.init(latitude: latDouble, longitude: LongDouble)
        } else {
            return nil
        }
    }
    
    init(CLLoc: CLLocation) {
        self.init(latitude: CLLoc.coordinate.latitude, longitude: CLLoc.coordinate.longitude)
    }
    
    static func returnOptCLLocationCoord(fromLatLongString latLongString: String) -> CLLocationCoordinate2D? {
        let latLong = latLongString.components(separatedBy: "- ")
        if let latStr = latLong.first, let longStr = latLong.last, let latDouble: CLLocationDegrees = Double("\(latStr)"), let LongDouble: CLLocationDegrees = Double("\(longStr)") {
            return CLLocationCoordinate2D(latitude: latDouble, longitude: LongDouble)
            
        }
        return nil
    }
    
    func asGogCL2D() -> GoogleMapsService.LocationCoordinate2D { return GoogleMapsService.LocationCoordinate2D(latitude: self.latitude, longitude: self.longitude) }
    
}

extension CLLocation {
     convenience init(locCord2D Cl2d: CLLocationCoordinate2D) {
        self.init(latitude: Cl2d.latitude, longitude: Cl2d.longitude)
    }
}

extension GoogleMapsService.LocationCoordinate2D: Equatable { }
public func ==(lhs: GoogleMapsService.LocationCoordinate2D, rhs: GoogleMapsService.LocationCoordinate2D) -> Bool {
    if lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude { return true }
    return false
}

public extension GoogleMapsService.LocationCoordinate2D {
    init(CLLoc2D: CLLocationCoordinate2D) {
        self.init(latitude: CLLoc2D.latitude, longitude: CLLoc2D.longitude)
    }
    func asCLLoc2D() -> CLLocationCoordinate2D { return CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude) }
}



extension Double {
    var ft: Double { return self * 3.28084 }
    var mi: Double { return self * 0.000621371192237 }
    var km: Double { return self / 1000 }
    var kmFromFeet: Double { return (self / 3.28084).km }
    var mFromFeet: Double  { return (self / 3.28084) }
    var displayUnits: Double {
        if boolUseMetricUnitsDisplay { return self.km } else { return self.mi }
    }
    func roundTo(places:Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

func containSameElements<T: Comparable>(_ array1: [T], _ array2: [T]) -> Bool {
    guard array1.count == array2.count else {
        return false // No need to sorting if they already have different counts
    }
    return array1.sorted() == array2.sorted()
}

extension Array {
    subscript (safe index: UInt) -> Element? {
        return Int(index) < count ? self[Int(index)] : nil
    }
}

extension UIColor {
    convenience init(red: Int, green: Int, blue: Int) {
        let newRed = CGFloat(red)/255
        let newGreen = CGFloat(green)/255
        let newBlue = CGFloat(blue)/255
        
        self.init(red: newRed, green: newGreen, blue: newBlue, alpha: 1.0)
    }
}

extension UIView {
    
    var safeTopAnchor: NSLayoutYAxisAnchor {
        if #available(iOS 11.0, *) {
            return self.safeAreaLayoutGuide.topAnchor
        } else {
            return self.topAnchor
        }
    }
    
    var safeLeftAnchor: NSLayoutXAxisAnchor {
        if #available(iOS 11.0, *){
            return self.safeAreaLayoutGuide.leftAnchor
        }else {
            return self.leftAnchor
        }
    }
    
    var safeRightAnchor: NSLayoutXAxisAnchor {
        if #available(iOS 11.0, *){
            return self.safeAreaLayoutGuide.rightAnchor
        }else {
            return self.rightAnchor
        }
    }
    
    var safeBottomAnchor: NSLayoutYAxisAnchor {
        if #available(iOS 11.0, *) {
            return self.safeAreaLayoutGuide.bottomAnchor
        } else {
            return self.bottomAnchor
        }
    }
    
    var safeBottomPadding: CGFloat {
        if #available(iOS 11.0, *), let kyWdw = UIApplication.shared.keyWindow  {
            return kyWdw.safeAreaInsets.bottom
        } else if let kyWdw = UIApplication.shared.keyWindow {
            return kyWdw.safeBottomPadding
        } else {
            return 30
        }
    }
}

















