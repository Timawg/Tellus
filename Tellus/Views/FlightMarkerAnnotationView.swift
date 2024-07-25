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
        // Create the UIImageView and add it as a subview
        let image = UIImage(systemName: "airplane")?.withRenderingMode(.alwaysTemplate)
        imageView = UIImageView(image: image)
        imageView.tintColor = .blue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        // Center the imageView within the annotation view
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
}


