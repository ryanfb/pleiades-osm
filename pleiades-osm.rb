#!/usr/bin/env ruby

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ENV['OSMLIB_XML_PARSER']='Expat'
require 'OSM/StreamParser'
require 'OSM/Database'
require 'OSM/objects'
require 'time'
require 'csv'

DISTANCE_THRESHOLD = 8.0

def haversine_distance(lat1, lon1, lat2, lon2)
	km_conv = 6371 # km
	dLat = (lat2-lat1) * Math::PI / 180
	dLon = (lon2-lon1) * Math::PI / 180
	lat1 = lat1 * Math::PI / 180
	lat2 = lat2 * Math::PI / 180

	a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.sin(dLon/2) * Math.sin(dLon/2) * Math.cos(lat1) * Math.cos(lat2)
	c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
	d = km_conv * c
end

# See:
#   https://en.wikipedia.org/wiki/Centroid#Centroid_of_polygon
#   https://github.com/geokit/geokit/blob/master/lib/geokit/polygon.rb#L45-L68
def centroid(nodes)
  centroid_lat = 0.0
  centroid_lon = 0.0
  signed_area = 0.0
  nodes[0...-1].each_index do |i|
    x0 = nodes[i].lat.to_f
    y0 = nodes[i].lon.to_f
    x1 = nodes[i+1].lat.to_f
    y1 = nodes[i+1].lon.to_f
    a = (x0 * y1) - (x1 * y0)
    signed_area += a
    centroid_lat += (x0 + x1) * a
    centroid_lon += (y0 + y1) * a
  end
  signed_area *= 0.5
  centroid_lat /= (6.0 * signed_area)
  centroid_lon /= (6.0 * signed_area)

  return OSM::Node.new(1, 'pleiades-osm', Time.new.xmlschema, centroid_lon, centroid_lat)
end

class PleiadesCallbacks < OSM::Callbacks
  attr_accessor :check_nodes, :database, :reparse, :pleiades_names, :pleiades_places

  def node(node)
    if reparse
      if @check_nodes.include?(node.id)
        $stderr.puts node.inspect
        return true
      else
        node.tags.keys.select{|t| t =~ /^name(:.+)?$/}.map{|t| node.tags[t]}.each do |osm_name|
          if osm_name && @pleiades_names.keys.include?(osm_name)
            $stderr.puts node.inspect
            @pleiades_names[osm_name].each do |place|
              if(haversine_distance(node.lat.to_f, node.lon.to_f, @pleiades_places[place]["reprLat"].to_f, @pleiades_places[place]["reprLong"].to_f) < DISTANCE_THRESHOLD)
                puts "#{place},#{node.inspect}"
                return true
              end
            end
          end
        end
      end
    end
    return false
  end

  def way(way)
    way.tags.keys.select{|t| t =~ /^name(:.+)?$/}.map{|t| way.tags[t]}.each do |osm_name|
      if osm_name && @pleiades_names.keys.include?(osm_name)
        $stderr.puts way.inspect
        if reparse
          nodes = way.nodes.map{|n| @database.get_node(n.to_i)}.reject{|n| n.nil?}
          way_centroid = nodes.first
          if nodes.first == nodes.last
            way_centroid = centroid(nodes)
          end
          $stderr.puts way_centroid.inspect
          @pleiades_names[osm_name].each do |place|
            if(haversine_distance(way_centroid.lat.to_f, way_centroid.lon.to_f, @pleiades_places[place]["reprLat"].to_f, @pleiades_places[place]["reprLong"].to_f) < DISTANCE_THRESHOLD)
              $stderr.puts "MATCH: #{place}\t#{way.id}\t#{osm_name}"
              puts "#{place},#{way.inspect}"
              return true
            end
          end
        else
          @check_nodes = (@check_nodes + way.nodes.map{|n| n.to_i}).uniq
        end
        # way.nodes.each do |node|
        #   $stderr.puts @database.get_node(node.to_i)
        # end
      end
    end

    return false
  end

  def relation(relation)
    relation.tags.keys.select{|t| t =~ /^name(:.+)?$/}.map{|t| relation.tags[t]}.each do |osm_name|
      if osm_name && @pleiades_names.keys.include?(osm_name)
        $stderr.puts relation.inspect
        return true
      end
    end

    return false
  end

  def initialize(db, names, places)
    @check_nodes = []
    @database = db
    @reparse = false
    @pleiades_names = names
    @pleiades_places = places
  end
end

osm_file, pleiades_places_csv, pleiades_names_csv = ARGV

places = {}
place_names = {}

$stderr.puts "Parsing Pleiades places..."
CSV.foreach(pleiades_places_csv, :headers => true) do |row|
  places[row["path"]] = row.to_hash
end
$stderr.puts places.keys.length

$stderr.puts "Parsing Pleiades names..."
CSV.foreach(pleiades_names_csv, :headers => true) do |row|
	unless places[row["pid"]].nil?
		places[row["pid"]]["names"] ||= []
		places[row["pid"]]["names"] << row.to_hash
	end

	[row["title"], row["nameAttested"], row["nameTransliterated"]].each do |name|
    unless name.nil?
      place_names[name] ||= []
      place_names[name] |= [row["pid"]]
    end
	end
end
$stderr.puts place_names.keys.length

db = OSM::Database.new
cb = PleiadesCallbacks.new(db, place_names, places)
parser = OSM::StreamParser.new(:filename => osm_file, :callbacks => cb)
$stderr.puts "Parsing OSM..."
parser.parse
$stderr.puts cb.check_nodes.inspect
$stderr.puts "Re-parsing OSM..."
cb.reparse = true
parser = OSM::StreamParser.new(:filename => osm_file, :callbacks => cb, :db => db)
parser.parse
$stderr.puts "#{db.nodes.keys.length} nodes"
$stderr.puts "#{db.ways.keys.length} ways"
$stderr.puts "#{db.relations.keys.length} relations"
db.clear
