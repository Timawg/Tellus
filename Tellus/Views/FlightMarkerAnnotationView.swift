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
        clusteringIdentifier = "flight"
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupImageView()
        clusteringIdentifier = "flight"
    }
    
    private func setupImageView() {
        let image = UIImage(systemName: "airplane")?.withRenderingMode(.alwaysTemplate)
        imageView = UIImageView(image: image)
        imageView.tintColor = UIColor(resource: .tellusDark)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
}


