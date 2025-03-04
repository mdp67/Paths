//
//  StepAnnotation.swift
//  Paths
//
//  Created by Mark Porcella on 12/11/16.
//  Copyright © 2016 Mark Porcella. All rights reserved.
//

import Foundation
import GoogleMaps
import GoogleMapsDirections
import MapKit

class StepAnnotation: NSObject {
    
//    var coordinate: GoogleMapsDirections.LocationCoordinate2D
//    var title: String?
//    var subtitle: String?
//    var isStraightWpt = false
//    
//    init(coordinate: GoogleMapsDirections.LocationCoordinate2D, title: String? = nil) {
//        self.coordinate = coordinate
//        self.title = title
//    }
//    
//    
//    
//    class func stringDistance(forFeet feet: Double) -> String {
//        if feet > 528 {
//            if boolUseMetricUnitsDisplay {
//                return String(format: "%0.1f km", feet.kmFromFeet)
//            } else {
//                return String(format: "%0.1f mi", feet / 5280)
//            }
//        } else {
//            if boolUseMetricUnitsDisplay {
//                let mRounded = round(10 * Double(round(feet.mFromFeet)))
//                return String(format: "%0.0f m", mRounded)
//            } else {
//                let ftRounded = round(10 * Double(round(feet / 10)))
//                return String(format: "%0.0f ft", ftRounded)
//            }
//        }
//    }
//    class func stringSpeech(forFeet feet: Double) -> String {
//        if boolUseMetricUnitsDisplay {
//            if let mRounded = Double(String(format: "%0.0f", round(10 * Double(round(feet.mFromFeet / 10))))) {
//                if mRounded > 580 { return "In \(String(format: "%0.1f", mRounded.km)) kilometers" }
//                else { return "In \(mRounded) meters" }
//            } else { return "" }
//        } else {
//            if let ftRounded =  Int(String(format: "%0.0f", round(10 * Double(round(feet / 10))))) {
//                switch ftRounded {
//                case let x where x > (5280 / 4) + 80: return "In \(String(format: "%0.1f", feet / 5280)) miles"
//                case let x where x < 1400 && x > 1240: return "In one quarter mile"
//                default: return "In \(ftRounded) feet"
//                }
//            } else { return ""}
//        }
//        
//    }
}
