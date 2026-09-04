import { Controller } from "@hotwired/stimulus"

// Leaflet ships as a UMD bundle, loaded by a plain script tag in the track
// layout, so it lives on the global object rather than being imported here.
export default class extends Controller {
  static values = { points: Array }

  connect() {
    const points = this.pointsValue
    if (points.length === 0) return

    this.readColors()

    // Canvas rather than SVG: a long crossing is thousands of fixes, and one
    // DOM node per fix crawls on a phone.
    this.map = L.map(this.element, { renderer: L.canvas() })

    this.addLayers()
    this.drawTrace(this.unwrapAntimeridian(points), points)

    L.control.scale({ imperial: false }).addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
    this.map = null
  }

  addLayers() {
    const chart = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    })

    // Sentinel-2 cloudless. The mosaic year is baked into the layer name, and
    // the WMTS path is {z}/{y}/{x}, not the usual {z}/{x}/{y}. Non-commercial
    // use only from the 2019 mosaic onwards.
    const satellite = L.tileLayer(
      "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg",
      {
        maxZoom: 14,
        attribution: 'Sentinel-2 cloudless 2024 <a href="https://s2maps.eu">s2maps.eu</a> by EOX (CC BY-NC-SA 4.0)'
      }
    )

    const seamarks = L.tileLayer("https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: '&copy; <a href="https://www.openseamap.org">OpenSeaMap</a>'
    })

    chart.addTo(this.map)
    seamarks.addTo(this.map)

    L.control.layers(
      { "Carte": chart, "Satellite": satellite },
      { "Balisage": seamarks }
    ).addTo(this.map)
  }

  // The palette lives in track.css; reading it back keeps one source of truth.
  // The boat is an ordinary DOM node, so it is styled there directly.
  readColors() {
    this.traceColor =
      getComputedStyle(this.element).getPropertyValue("--track-trace-color").trim() || "#e5484d"
  }

  drawTrace(latlngs, points) {
    L.polyline(latlngs, { color: this.traceColor, weight: 2 }).addTo(this.map)

    const lastIndex = latlngs.length - 1

    latlngs.forEach((latlng, index) => {
      if (index === lastIndex) return

      this.describe(L.circleMarker(latlng, {
        radius: 4,
        color: this.traceColor,
        fillColor: this.traceColor,
        fillOpacity: 0.6,
        weight: 2
      }), points[index].label)
    })

    // The boat rides the last known fix. That is the one thing family ashore
    // opens this page for, so it gets a hull instead of another dot.
    this.describe(L.marker(latlngs[lastIndex], {
      icon: this.boatIcon(),
      zIndexOffset: 1000,
      keyboard: false
    }), points[lastIndex].label)

    if (latlngs.length === 1) {
      this.map.setView(latlngs[0], 8)
    } else {
      this.map.fitBounds(L.latLngBounds(latlngs), { padding: [ 32, 32 ] })
    }
  }

  // Hover shows the date on a desktop; the popup covers the tap on a phone,
  // where there is no hover to speak of.
  describe(marker, label) {
    marker
      .bindTooltip(label, { direction: "top", offset: [ 0, -8 ] })
      .bindPopup(label)
      .addTo(this.map)
  }

  boatIcon() {
    return L.divIcon({
      className: "track-boat",
      iconSize: [ 26, 26 ],
      iconAnchor: [ 13, 20 ],
      tooltipAnchor: [ 0, -10 ],
      html: '<svg viewBox="0 0 24 24" aria-hidden="true">' +
        '<path d="M11 1.5 3.6 12.2H11zM13 5.4V12.2h5.8zM1.8 14.2h20.4l-3.3 6.3H5.1z"/>' +
        "</svg>"
    })
  }

  // A Pacific crossing hands us longitudes that jump from +179 to -179.
  // Left alone, the polyline draws a stripe right across the map, so keep
  // each fix within half a world of the previous one.
  unwrapAntimeridian(points) {
    let offset = 0

    return points.map((point, index) => {
      if (index > 0) {
        const delta = point.lon - points[index - 1].lon
        if (delta > 180) offset -= 360
        if (delta < -180) offset += 360
      }

      return [ point.lat, point.lon + offset ]
    })
  }
}
