import MapKit

@MainActor
@Observable
final class LiveFlightsModel {
    struct Selection: Identifiable, Equatable {
        let id: String
        let requestID = UUID()
    }

    private let flightService: FlightServiceProtocol
    private let detailsService: FlightDetailsServiceProtocol
    private let preferences: MapPreferencesStore
    @ObservationIgnored private var visibleRect: MKMapRect?
    @ObservationIgnored private var isMapActive = false
    @ObservationIgnored private var isViewportChanging = false
    @ObservationIgnored private var flightUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var lastOpenSkyFlights: [LiveFlight] = []
    private var liveFlights: [String: LiveFlight] = [:]

    private(set) var markerSnapshot = FlightMarkerSnapshot([])
    private(set) var totalFlightCount = 0
    private(set) var flightsPausedUntil: Date?
    private(set) var selectedAircraft: AircraftInfo?
    private(set) var selectedRoute: FlightRoute?
    private(set) var isLoadingFlightDetails = false
    var selection: Selection? {
        didSet {
            guard let selection, selection != oldValue else { return }
            selectedAircraft = nil
            selectedRoute = nil
            isLoadingFlightDetails = true
        }
    }

    var selectedMapRoute: FlightRoute? {
        // The sheet keeps its details during dismissal. The map clears the route immediately.
        selection == nil ? nil : selectedRoute
    }

    /// MapKit selects by ICAO address. The details sheet binds to the identifiable selection.
    var selectedFlightID: String? {
        get { selection?.id }
        set {
            guard selection?.id != newValue else { return }
            selection = newValue.map(Selection.init(id:))
        }
    }

    var showsFlights: Bool {
        didSet {
            guard showsFlights != oldValue else { return }
            preferences[.flights] = showsFlights
            if showsFlights {
                startPollingIfNeeded()
            } else {
                stopPolling()
                selection = nil
                if !markerSnapshot.markers.isEmpty { markerSnapshot = FlightMarkerSnapshot([]) }
                liveFlights = [:]
                lastOpenSkyFlights = []
                totalFlightCount = 0
                flightsPausedUntil = nil
            }
        }
    }

    var isShowingSubsetOfFlights: Bool {
        markerSnapshot.markers.count < totalFlightCount
    }

    // MapKit starts to stutter beyond a few hundred moving markers.
    private static let maxVisibleFlights = 500

    init(flightService: FlightServiceProtocol, detailsService: FlightDetailsServiceProtocol, preferences: MapPreferencesStore) {
        self.flightService = flightService
        self.detailsService = detailsService
        self.preferences = preferences
        showsFlights = preferences[.flights]
    }

    deinit {
        flightUpdateTask?.cancel()
    }

    func flight(for icao24: String) -> LiveFlight? {
        liveFlights[icao24.lowercased()]
    }

    func loadFlightDetails(for request: Selection?) async {
        guard !Task.isCancelled, let request, selection == request else { return }
        let id = request.id
        let callsign = flight(for: id)?.callsign ?? ""
        async let aircraft = try? detailsService.getAircraft(icao24: id)
        async let route = callsign.isEmpty ? nil : try? detailsService.getRoute(callsign: callsign)
        let loadedRoute = await route

        guard !Task.isCancelled, selection == request else { return }
        if let loadedRoute, let coordinate = flight(for: id)?.coordinate,
           loadedRoute.isPlausible(forAircraftAt: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
            selectedRoute = loadedRoute
        }

        let loadedAircraft = await aircraft
        guard !Task.isCancelled, selection == request else { return }
        selectedAircraft = loadedAircraft
        isLoadingFlightDetails = false
    }

    func setMapActive(_ isActive: Bool) {
        isMapActive = isActive
        if isActive {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    func viewportWillChange() {
        isViewportChanging = true
        stopPolling()
    }

    func updateViewport(_ rect: MKMapRect) {
        isViewportChanging = false
        if visibleRect.map({ MKMapRectEqualToRect($0, rect) }) != true {
            stopPolling()
            visibleRect = rect
        }
        startPollingIfNeeded()
    }

    private func startPollingIfNeeded() {
        guard isMapActive, showsFlights, !isViewportChanging,
              flightUpdateTask == nil, let viewport = visibleRect else { return }
        flightUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.pollFlights(in: viewport) != nil else { return }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func stopPolling() {
        flightUpdateTask?.cancel()
        flightUpdateTask = nil
    }

    private func openSkyFlights(in region: (latitude: CoordinateSpan, longitude: CoordinateSpan)) async -> Result<[LiveFlight], Error> {
        do {
            return .success(try await flightService.getFlights(latitudeSpan: region.latitude, longitudeSpan: region.longitude))
        } catch {
            return .failure(error)
        }
    }

    private func pollFlights(in viewport: MKMapRect) async {
        let visibleRegion = MapRegionCalculator.bounds(of: viewport)
        async let openSky = openSkyFlights(in: visibleRegion)
        async let military = try? flightService.getMilitaryFlights()
        let (openSkyResult, militaryFlights) = await (openSky, military)

        // Viewport changes and map deactivation both cancel the previous poll.
        guard !Task.isCancelled else { return }
        switch openSkyResult {
        case .success(let flights):
            lastOpenSkyFlights = flights
            flightsPausedUntil = nil
        case .failure(HTTPError.rateLimited(let retryAfter)):
            flightsPausedUntil = retryAfter.map { Date().addingTimeInterval($0) }
        case .failure(let error):
            print(error)
        }

        let militaryInView = (militaryFlights ?? []).filter {
            visibleRegion.latitude.contains($0.coordinate.latitude)
                && visibleRegion.longitude.contains($0.coordinate.longitude)
        }
        let flights = lastOpenSkyFlights.merging(military: militaryInView)
        var flightsByID: [String: LiveFlight] = [:]
        var markers: [FlightMarker] = []
        for flight in flights where flightsByID[flight.id] == nil {
            flightsByID[flight.id] = flight
            markers.append(FlightMarker(flight: flight))
        }
        liveFlights = flightsByID
        let sample = markers.distributed(in: viewport, limit: Self.maxVisibleFlights, keeping: selectedFlightID)
        totalFlightCount = sample.visibleCount
        if markerSnapshot.markers != sample.markers {
            markerSnapshot = FlightMarkerSnapshot(sample.markers)
        }
    }
}
