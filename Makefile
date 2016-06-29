SHELL:=/bin/bash

all: pleiades-osm.csv

turkey-latest.osm:
	wget 'http://download.geofabrik.de/europe/turkey-latest.osm.bz2'
	bunzip2 turkey-latest.osm.bz2

pleiades-places-latest.csv:
	wget http://atlantides.org/downloads/pleiades/dumps/$@.gz
	gunzip $@.gz

pleiades-names-latest.csv:
	wget http://atlantides.org/downloads/pleiades/dumps/$@.gz
	gunzip $@.gz

pleiades-osm.csv: pleiades-osm.rb pleiades-places-latest.csv pleiades-names-latest.csv
	bundle exec ./pleiades-osm.rb turkey-latest.osm pleiades-places-latest.csv pleiades-names-latest.csv > $@

clean:
	rm -vf pleiades-*-latest.csv *.osm
