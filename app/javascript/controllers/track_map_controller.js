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
  readColors() {
    const styles = getComputedStyle(this.element)

    this.traceColor = styles.getPropertyValue("--track-trace-color").trim() || "#e5484d"
    this.lastFixColor = styles.getPropertyValue("--track-last-fix-color").trim() || "#0b7285"
  }

  drawTrace(latlngs, points) {
    L.polyline(latlngs, { color: this.traceColor, weight: 2 }).addTo(this.map)

    latlngs.forEach((latlng, index) => {
      const isLast = index === latlngs.length - 1

      L.circleMarker(latlng, {
        radius: isLast ? 7 : 4,
        color: isLast ? this.lastFixColor : this.traceColor,
        fillColor: isLast ? this.lastFixColor : this.traceColor,
        fillOpacity: isLast ? 1 : 0.6,
        weight: 2
      })
        .bindPopup(points[index].label)
        .addTo(this.map)
    })

    if (latlngs.length === 1) {
      this.map.setView(latlngs[0], 8)
    } else {
      this.map.fitBounds(L.latLngBounds(latlngs), { padding: [ 32, 32 ] })
    }
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
