//
//  MainViewController.swift
//  MetalSplat
//
//  Created by CC Laan on 9/16/23.
//

import Foundation
import UIKit
import SwiftUI



struct SplatChoiceView: View {
    
    var body: some View {
        NavigationView {
            
            List {
                
                Text("Metal Splat Demo").font(.largeTitle)
                
                Group {
                                                            
                    Section(header: Text("AR Demos")) {
                        
                        NavigationLink(destination: ARSplatView(model: Models.Mic ) ) {
                            Label("Mic", systemImage: "arkit")
                        }
                        
                        NavigationLink(destination: ARSplatView(model: Models.MicLowRes ) ) {
                            Label("Mic - Low Res", systemImage: "arkit")
                        }
                        
                        NavigationLink(destination: ARSplatView(model: Models.Lego )) {
                            Label("Lego", systemImage: "arkit")
                        }
                        
                        /*
                        NavigationLink(destination: ARSplatView(model: Models.Plush )) {
                            Label("Plush", systemImage: "arkit")
                        }
                        
                        NavigationLink(destination: ARSplatView(model: Models.Nike )) {
                            Label("Nike", systemImage: "arkit")
                        }
                                                
                        NavigationLink(destination: ARSplatView(model: Models.Drums )) {
                            Label("Drums", systemImage: "arkit")
                        }
                         */
                    }
                    
                    Section(header: Text("Non-AR Demos")) {
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.Mic)) {
                            Label("Mic", systemImage: "cube")
                        }
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.MicLowRes)) {
                            Label("Mic - Low Res", systemImage: "cube")
                        }
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.Lego)) {
                            Label("Lego", systemImage: "cube")
                        }
                        
                        /*
                        NavigationLink(destination: SplatSimpleView(model: Models.Ship)) {
                            Label("Ship", systemImage: "cube")
                        }
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.Plush)) {
                            Label("Plush", systemImage: "cube")
                        }
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.Nike)) {
                            Label("Nike", systemImage: "cube")
                        }
                        
                        
                        NavigationLink(destination: SplatSimpleView(model: Models.Drums)) {
                            Label("Drums", systemImage: "cube")
                        }
                        */
                        
                        
                        
                        
                        
                    }
                }
            }
        }.statusBarHidden(true)
    }
}



class MainViewController : UIViewController {
    
    override func viewDidAppear(_ animated: Bool) {
        
        //let view = ARSplatView()
        //let view = SplatSimpleView()
        
        let view = SplatChoiceView()
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        
        self.present(host, animated: false)
        
    }
}
