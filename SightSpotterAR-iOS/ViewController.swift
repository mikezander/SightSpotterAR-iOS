//
//  ViewController.swift
//  SightSpotterAR-iOS
//
//  Created by Michael Alexander on 10/13/17.
//  Copyright © 2017 Michael Alexander. All rights reserved.
//

import UIKit
import SpriteKit
import ARKit
import CoreLocation
import GameplayKit
import SwiftyJSON

class ViewController: UIViewController, ARSKViewDelegate, CLLocationManagerDelegate {
    
    let locationManager = CLLocationManager()
    var userLocation = CLLocation()
    var sightsJSON: JSON!
    var userHeading = 0.0
    var headingCOunt = 0
    var pages = [UUID:String]()
    
    @IBOutlet var sceneView: ARSKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and node count
        sceneView.showsFPS = true
        sceneView.showsNodeCount = true
        
        // Load the SKScene from 'Scene.sks'
        if let scene = SKScene(fileNamed: "Scene") {
            sceneView.presentScene(scene)
        }
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = AROrientationTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSKViewDelegate
    
    func view(_ view: ARSKView, nodeFor anchor: ARAnchor) -> SKNode? {
       
        return nil
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse{
            
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error.localizedDescription)
    }
    
    func fetchSights(){
        
        let urlString = "https://en.wikipedia.org/w/api.php?ggscoord=\(userLocation.coordinate.latitude)%7C\(userLocation.coordinate.longitude)&action=query&prop=coordinates%7Cpageimages%7Cpageterms&colimit=50&piprop=thumbnail&pithumbsize=500&pilimit=50&wbptterms=description&generator=geosearch&ggsradius=10000&ggslimit=50&format=json"
        
        guard let url = URL(string: urlString) else{ return }
        
        if let data = try? Data(contentsOf: url){
            
            sightsJSON = JSON(data)
            locationManager.startUpdatingHeading()
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        guard let location = locations.last else{ return }
        userLocation = location
        
        DispatchQueue.global().async {
            self.fetchSights()
        }
    }
    
    func createSights(){
        
        //1 - loop over all pages from wikipedia
        for page in sightsJSON["query"]["pages"].dictionaryValue.values{
            
            //2 - pull out this pages coordinates and make a location form them
            let locationLat = page["coordinates"][0]["lon"].doubleValue
            let locationLon = page["coordinates"][0]["lon"].doubleValue
            let location = CLLocation(latitude: locationLat, longitude: locationLon)
            
            //3 - calculate the distance from the user to this point, then calculate its azimuth
            let distance = Float(userLocation.distance(from: location))
            let azimuthFromUser = direction(from: userLocation, to: location)
            
            //4 - calculate the angle from the user to that direction
            let angle = azimuthFromUser - userHeading
            let angleRadians = deg2rad(angle)
            
            //5 - create a horizontal rotation matrix
            let rotationHorizontal = matrix_float4x4(SCNMatrix4MakeRotation(Float(angleRadians), 1, 0, 0))
            
            //6 - create a verticl rotation matrix
            let roatationVertical = matrix_float4x4(SCNMatrix4MakeRotation(-0.2 + Float(distance / 600), 0, 1, 0))
            
            //7 - combine the horizontal and vertical matrices, then combine that with the camera transform
            let rotation = simd_mul(rotationHorizontal, roatationVertical)
            guard let sceneView = self.view as? ARSKView else{ return }
            guard let frame = sceneView.session.currentFrame else { return }
            let rotation2 = simd_mul(frame.camera.transform, rotation)
            
            //8 - create a matrix that lets us position the anchor into the screen, then combine that with our combined matrix so far
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -(distance / 50)
            
            let transform = simd_mul(rotation2, translation)
            
            // create an new anchor using the final matrix, then add it to our pages dictionary
            let anchor = ARAnchor(transform: transform)
            sceneView.session.add(anchor: anchor)
            pages[anchor.identifier] = page ["title"].string ?? "Uknown"
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
       
        DispatchQueue.main.async {
            self.headingCOunt += 1
            if self.headingCOunt != 2 { return }
            
            self.userHeading = newHeading.magneticHeading
            self.locationManager.stopUpdatingHeading()
            self.createSights()
        }
    }
    
    // Algorithm: calculate bearing from one point to another
    func deg2rad(_ degrees: Double)-> Double{
        return degrees * Double.pi / 180
    }
    
    func rad2deg(_ radians: Double)-> Double{
        return radians * 180 / Double.pi
    }
    
    func direction(from pl: CLLocation, to p2: CLLocation)-> Double{
        
        let lon_delta = p2.coordinate.longitude - pl.coordinate.longitude
        let y = sin(lon_delta) * cos(p2.coordinate.longitude)
        let x = cos(pl.coordinate.longitude) * sin(p2.coordinate.longitude) - sin(pl.coordinate.longitude) * cos(p2.coordinate.longitude) * cos(lon_delta)
        let radians = atan2(y,x)
        
        return rad2deg(radians)
    }
    
    
}
