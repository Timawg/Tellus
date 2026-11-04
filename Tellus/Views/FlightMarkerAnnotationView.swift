//
//  FlightAnnotationMarkerView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-25.
//

import Foundation
import MapKit

final class FlightMarkerAnnotationView: MKAnnotationView {
    
    private var imageView: UIImageView!

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupImageView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupImageView()
    }
    
    private func setupImageView() {
        let image = UIImage(imageLiteralResourceName: "aircraft")
        imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Drop shadow so aircraft stand out against the map.
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 3
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        imageView.layer.masksToBounds = false
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 25),
            imageView.widthAnchor.constraint(equalToConstant: 20),
        ])
    }
}


