SHELL:=/bin/bash

all: pleiades-osm.csv

turkey-latest.osm.pbf:
	wget 'http://download.geofabrik.de/europe/turkey-latest.osm.pbf'

pleiades-places-latest.csv:
	wget http://atlantides.org/downloads/pleiades/dumps/$@.gz
	gunzip $@.gz

pleiades-names-latest.csv:
	wget http://atlantides.org/downloads/pleiades/dumps/$@.gz
	gunzip $@.gz

pleiades-osm.csv: pleiades-osm.rb pleiades-places-latest.csv pleiades-names-latest.csv turkey-latest.osm.pbf
	bundle exec ./pleiades-osm.rb turkey-latest.osm.pbf pleiades-places-latest.csv pleiades-names-latest.csv > $@

clean:
	rm -vf pleiades-*-latest.csv *.osm *.osm.pbf
