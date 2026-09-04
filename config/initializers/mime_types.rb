# The trace is also served as KML, so it can be opened in Google Earth where
# the time slider replays a crossing day by day.
Mime::Type.register "application/vnd.google-earth.kml+xml", :kml
