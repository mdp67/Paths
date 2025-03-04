//
//  ElevationCalculatorProtocol.swift
//  Paths
//
//  Created by Mark Porcella on 7/24/17.
//  Copyright © 2017 Mark Porcella. All rights reserved.
//

import Foundation
import GoogleMaps
import GooglePlaces
import GoogleMapsDirections
import Polyline
import MapKit
import Alamofire
import ObjectMapper

protocol ElevationCalculator: class {
    var googleRt: GoogleMapsDirections.Response.Route? { get set }
    var totalDistance: Int? { get }
    var previousElevationRequestURL: URL? { get set }
    
    func startCalculatingElevations()
    func errorFindingElevations(errorString: String)
    func completedElevation(with elevationPts: [ElevationPoint], gain: Double, lost: Double, max: Double, min: Double, url: URL)
}

extension ElevationCalculator {

    func calculateElevations() {
        
        guard let gglRt = self.googleRt else { return }
        var coordinatesForCombinedPath = [CLLocationCoordinate2D]()
        gglRt.legs.forEach{ $0.steps.forEach { step in
            if let plylnpts = step.polylinePoints, let gmsPath = GMSPath(fromEncodedPath: plylnpts) {
                for i in 0..<gmsPath.count() { // can't for-in loop the GMSPath Coords, have to get them through coordinate(at:)
                    let coord = gmsPath.coordinate(at: i)
                    coordinatesForCombinedPath.append(coord)
                }
            }
        }  }

        guard let urlGog = returnURLStringForCoords(pathCoords: coordinatesForCombinedPath, shortenURL: false) else { errorFindingElevations(errorString: "Error Building Google Request URL"); return }
        Alamofire.request(urlGog).responseJSON { (response) in
            
            if response.result.isFailure { self.errorFindingElevations(errorString: ""); return }
            // Nil
            if let _ = response.result.value as? NSNull { self.errorFindingElevations(errorString: "Something went wrong and Google isn't telling us what, please try again later"); return }
            // JSON
            guard let json = response.result.value as? [String : AnyObject] else { self.errorFindingElevations(errorString: "Google gave Paths a weird response that we can't decode, please try again later"); return }
            guard let response = Mapper<Response>().map(JSON: json) else { self.errorFindingElevations(errorString: "Google gave Paths a weird response that we can't decode, please try again later"); return }
            if let responseCode = response.status {
                switch responseCode {
                case .ok: break
                case .invalidRequest: self.errorFindingElevations(errorString: "The request looks weird to Google, please try again"); return
                case .overQueryLimit: self.errorFindingElevations(errorString: "It looks like you've gone over the query limit placed by Google, please delay 5 min, and try again"); return
                case .requestDenied: self.errorFindingElevations(errorString: "Google denied request, Paths isn't paying them and sometimes Google gets cranky :-("); return
                case .unknownError: self.errorFindingElevations(errorString: "Something went wrong and Google isn't telling us what, please try again later"); return
                }
            }
            
            if let elvtnPts = response.elevations {
                var gain: Double = 0.0
                var lost: Double = 0.0
                var max: Double = 0.0
                var min: Double = 0.0
                guard var startElevation = elvtnPts.first?.elevation else { return }
                max = startElevation
                min = startElevation
                for pt in elvtnPts.dropFirst() {
                    if let ptEl = pt.elevation {
                        
                            if ptEl >= startElevation {
                                if ptEl > max { max = ptEl } // already looping, might as well do this instead of using the function...
                                gain += ( ptEl - startElevation )
                            } else {
                                if ptEl < min { min = ptEl }
                                lost += ( startElevation - ptEl  )
                            }
                            startElevation = ptEl
                    }
                }
                self.completedElevation(with: elvtnPts, gain: gain, lost: lost, max: max, min: min, url: urlGog)
            }
        }
    }
    
    func returnURLStringForCoords(pathCoords: [CLLocationCoordinate2D], shortenURL: Bool) -> URL? {
        // max URL request limit is 8172 char long - Google URL reqeust length restriction in '17 https://developers.google.com/maps/documentation/elevation/intro#Limits
        // I create a path with the combined coordinates from the Google route (the rt.Google is in segments, combining them deosn't work), the encoded path is the longest part of the URL
        // Limiting the pts in the path 2200 seems to work about right, so I created an array extension to pull evenly spaced coordinates from the array
        // sometimes 2200 is still to many, so I check again after the URL is built and pull more if it's still too long
        
        var pthCrds = pathCoords
        pthCrds.dropEvenlySpacedElementsToHaveTotalElementsLessThan(maxNumElements: 2200) // about right to minimize rebuilding the path
        var urlString = "https://maps.googleapis.com/maps/api/elevation/json?path=enc:"
        var polyline: Polyline!
        if shortenURL {
            pthCrds.dropElementsAtMulitiples(of: 12)
            polyline = Polyline(coordinates: pthCrds)
        } else {
            polyline = Polyline(coordinates: pthCrds)
        }
        let encodedPolyline: String = polyline.encodedPolyline
        urlString += encodedPolyline
        urlString += "&samples=500" // the most Google wants to give
        urlString += "&key=AIzaSyA4GaeHp8Tl6OlCJ-B8fZ1A4Nx5cZyFCa4"
        let escapedURLString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
        guard let urlGog = URL(string: escapedURLString!) else { return nil }
        
        if urlGog.absoluteString.characters.count > 8192  { // recurse if it's still too long
            return returnURLStringForCoords(pathCoords: pthCrds, shortenURL: true)
        } else {
            return urlGog
        }
    }
}


extension Array {
    
    mutating func dropEvenlySpacedElementsToHaveTotalElementsLessThan(maxNumElements: Int) {
        
        let numElements = self.count
        if numElements < maxNumElements { return }
        let numElementsToRemove = numElements - maxNumElements
        let percentNeedToRemove = Float(numElementsToRemove) / Float(numElements)
        switch percentNeedToRemove {
        case 0..<0.05: self.dropElementsAtMulitiples(of: 15)
        case 0.05..<0.1: self.dropElementsAtMulitiples(of: 10)
        case 0.1..<0.2: self.dropElementsAtMulitiples(of: 7)
        case 0.2..<0.3: self.dropElementsAtMulitiples(of: 6)
        case 0.3..<0.4: self.dropElementsAtMulitiples(of: 5)
        case 0.4..<0.5: self.dropElementsAtMulitiples(of: 5)
        case 0.5..<0.6: self.dropElementsAtMulitiples(of: 3)
        case 0.6..<0.9: self.dropElementsAtMulitiples(of: 2)
        default: self.dropElementsAtMulitiples(of: 2)
        }
        if self.count > maxNumElements {
            dropEvenlySpacedElementsToHaveTotalElementsLessThan(maxNumElements: maxNumElements)
        }
    }
    
    mutating func dropElementsAtMulitiples(of indexToDrop: Int) {
        var newSelf = [Element]()
        for (loopIndx, elmnt) in self.enumerated() {
            if (loopIndx + 1) % indexToDrop == 0 { continue }
            newSelf.append(elmnt)
        }
        self = newSelf
    }
}

public enum StatusCode: String {
    case ok = "OK"
    case invalidRequest = "INVALID_REQUEST"
    case overQueryLimit = "OVER_QUERY_LIMIT"
    case requestDenied = "REQUEST_DENIED"
    case unknownError = "UNKNOWN_ERROR"
}

public struct Response: Mappable {
    public var status: StatusCode?
    public var errorMessage: String?
    public var elevations: [ElevationPoint]?
    public init?(map: Map) { }
    public mutating func mapping(map: Map) {
        
        status <- (map["status"], EnumTransform())
        errorMessage <- map["error_message"]
        elevations <- map["results"]
    }    
}

public struct ElevationPoint: Mappable {
    public var elevation: Double?
    public var location: GoogleMapsService.LocationCoordinate2D?
    public var resolution: Double?
    
    public init?(map: Map) { }
    public mutating func mapping(map: Map) {
        elevation <- map["elevation"]
        location <- (map["location"], LocationCoordinate2DTransform())
        resolution <- map["resolution"]
    }
}


class LocationCoordinate2DTransform: TransformType {
    typealias LocationCoordinate2D = GoogleMapsService.LocationCoordinate2D
    typealias Object = LocationCoordinate2D
    typealias JSON = [String : Any]
    
    func transformFromJSON(_ value: Any?) -> Object? {
        if let value = value as? JSON {
            guard let latitude = value["lat"] as? Double, let longitude = value["lng"] as? Double else {
                NSLog("Error: lat/lng is not Double")
                return nil
            }
            return LocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return nil
    }
    
    func transformToJSON(_ value: Object?) -> JSON? {
        if let value = value {
            return [
                "lat" : "\(value.latitude)",
                "lng" : "\(value.longitude)"
            ]
        }
        return nil
    }
}

open class EnumTransform<T: RawRepresentable>: TransformType {
    public typealias Object = T
    public typealias JSON = T.RawValue
    
    public init() {}
    
    open func transformFromJSON(_ value: Any?) -> T? {
        if let raw = value as? T.RawValue {
            return T(rawValue: raw)
        }
        return nil
    }
    
    open func transformToJSON(_ value: T?) -> T.RawValue? {
        if let obj = value {
            return obj.rawValue
        }
        return nil
    }
}

//     func calculateElevations() {
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
//        urlString += "&samples="
//        urlString += returnSringCalcNumElevationSamples()
//        urlString += "&key=AIzaSyA4GaeHp8Tl6OlCJ-B8fZ1A4Nx5cZyFCa4"
//
//        //        let escapedAddress = address.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
//        let escapedURLString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
//
//        let error = NSError(domain: "Error Building Google Request URL", code: 0, userInfo: nil)
//        guard let urlGog = URL(string: escapedURLString!)  else { errorFindingElevations(error: error); return }
//        if let prvElRqstURL = previousElevationRequestURL, prvElRqstURL == urlGog { return } // don't calculate the same thig
//
//        let urlRequest = URLRequest(url: urlGog)
//        let config = URLSessionConfiguration.default
//        let session = URLSession(configuration: config)
//        let task = session.dataTask(with: urlRequest) { [unowned self] (optData, optResponse, optError) in
//
//            if let error = optError as NSError? { self.errorFindingElevations(error: error)  }
//            if let data = optData {
//                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
//                    if let dict = json as? [String : Any] {
//                        if let arrayOfDict = dict["results"] as? [[String: Any]] {
//                            var elevations = [Double]()
//                            for locDict in arrayOfDict {
//                                if let elevation = locDict["elevation"] as? Double {
//                                    elevations.append(elevation)
//                                }
//                            }
//                            var gain: Double = 0.0
//                            var lost: Double = 0.0
//                            var max: Double = 0.0
//                            var min: Double = 0.0
//                            guard var startElevation = elevations.first else { return }
//                            max = startElevation
//                            min = startElevation
//                            for elevation in elevations.dropFirst() {
//                                if elevation >= startElevation {
//                                    if elevation > max { max = elevation }
//                                    gain += ( elevation - startElevation )
//                                } else {
//                                    if elevation < min { min = elevation }
//                                    lost += ( startElevation - elevation  )
//                                }
//                                startElevation = elevation
//                            }
//                            self.completedElevation(with: elevations, gain: gain, lost: lost, max: max, min: min, url: urlGog)
//                        }
//                    }
//                }
//            }
//        }
//        task.resume()
//    }

/////////////////// was working prior to using AlamoFir
//        if let prvElRqstURL = previousElevationRequestURL, prvElRqstURL == urlGog { return } // don't calculate the same thig
//
//        let urlRequest = URLRequest(url: urlGog)
//        let config = URLSessionConfiguration.default
//        let session = URLSession(configuration: config)
//        let task = session.dataTask(with: urlRequest) { [unowned self] (optData, optResponse, optError) in
//
//            if let error = optError as NSError? { self.errorFindingElevations(error: error)  }
//            if let data = optData {
//                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
//                    if let dict = json as? [String : Any] {
//                        if let arrayOfDict = dict["results"] as? [[String: Any]] {
//                            var elevations = [Double]()
//                            for locDict in arrayOfDict {
//                                if let elevation = locDict["elevation"] as? Double {
//                                    elevations.append(elevation)
//                                }
//                            }
//                            var gain: Double = 0.0
//                            var lost: Double = 0.0
//                            var max: Double = 0.0
//                            var min: Double = 0.0
//                            guard var startElevation = elevations.first else { return }
//                            max = startElevation
//                            min = startElevation
//                            for elevation in elevations.dropFirst() {
//                                if elevation >= startElevation {
//                                    if elevation > max { max = elevation }
//                                    gain += ( elevation - startElevation )
//                                } else {
//                                    if elevation < min { min = elevation }
//                                    lost += ( startElevation - elevation  )
//                                }
//                                startElevation = elevation
//                            }
//                            self.completedElevation(with: elevations, gain: gain, lost: lost, max: max, min: min, url: urlGog)
//                        }
//                    }
//                }
//            }
//        }
//        task.resume()
////////////////////////////




