import MapKit

enum MapRegionCalculator {
    static func fitting(_ border: CountryBorder, in viewport: MKMapRect) -> MKCoordinateRegion {
        let aspectRatio = viewport.height > 0 ? viewport.width / viewport.height : 402.0 / 874.0
        return MKCoordinateRegion(fitting: border.focusRect, aspectRatio: aspectRatio)
    }

    static func region(for country: Country) -> MKCoordinateRegion? {
        guard let area = country.area, area.isFinite, area > 0, country.latlng.count >= 2 else { return nil }
        let center = CLLocationCoordinate2D(latitude: country.latlng[0], longitude: country.latlng[1])
        guard CLLocationCoordinate2DIsValid(center) else { return nil }
        let latitudeDelta = sqrt(area) / 110
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: latitudeDelta * 2)
        )
    }

    static func bounds(of viewport: MKMapRect) -> (latitude: CoordinateSpan, longitude: CoordinateSpan) {
        let region = MKCoordinateRegion(viewport)
        return (
            CoordinateSpan(
                minimum: region.center.latitude - region.span.latitudeDelta / 2,
                maximum: region.center.latitude + region.span.latitudeDelta / 2
            ),
            CoordinateSpan(
                minimum: region.center.longitude - region.span.longitudeDelta / 2,
                maximum: region.center.longitude + region.span.longitudeDelta / 2
            )
        )
    }

    static func matches(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
        let tolerance = 0.000001
        return abs(lhs.center.latitude - rhs.center.latitude) < tolerance
            && abs(lhs.center.longitude - rhs.center.longitude) < tolerance
            && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < tolerance
            && abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < tolerance
    }
}
