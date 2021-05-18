//
//  sharedClass.swift
//  Presuno
//
//  Created by Muhammad Usman on 26/09/1442 AH.
//  Copyright © 1442 AH Softvelum, LLC. All rights reserved.
//

import UIKit

class sharedClass: NSObject {//This is shared class
    static let sharedInstance = sharedClass()

        //Show alert
        func alert(view: UIViewController, title: String, message: String) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let defaultAction = UIAlertAction(title: "OK", style: .default, handler: { action in
            })
            alert.addAction(defaultAction)
            DispatchQueue.main.async(execute: {
                view.present(alert, animated: true)
            })
        }

        private override init() {
        }
    }
