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

def centroid(nodes)
  avg_lat = nodes.map{|n| n.lat.to_f}.inject{ |sum, el| sum + el }.to_f / nodes.size
  avg_lon = nodes.map{|n| n.lon.to_f}.inject{ |sum, el| sum + el }.to_f / nodes.size
  return OSM::Node.new(1, 'pleiades-osm', Time.new.xmlschema, avg_lon, avg_lat)
end

class PleiadesCallbacks < OSM::Callbacks
  attr_accessor :check_nodes, :database, :reparse, :pleiades_names, :pleiades_places

  def node(node)
    if reparse
      if @check_nodes.include?(node.id)
        $stderr.puts node.inspect
        return true
      else
        if node.tags['name'] && @pleiades_names.keys.include?(node.tags['name'])
          $stderr.puts node.inspect
          @pleiades_names[node.tags['name']].each do |place|
            if(haversine_distance(node.lat.to_f, node.lon.to_f, @pleiades_places[place]["reprLat"].to_f, @pleiades_places[place]["reprLong"].to_f) < DISTANCE_THRESHOLD)
              puts "#{place},#{node.inspect}"
              return true
            end
          end
          return false
        end
      end
    end
    return false
  end

  def way(way)
    if way.tags['name'] && @pleiades_names.keys.include?(way.tags['name'])
      $stderr.puts way.inspect
      if reparse
        nodes = way.nodes.map{|n| @database.get_node(n.to_i)}.reject{|n| n.nil?}
        way_centroid = centroid(nodes)
        $stderr.puts way_centroid.inspect
        @pleiades_names[way.tags['name']].each do |place|
          if(haversine_distance(way_centroid.lat.to_f, way_centroid.lon.to_f, @pleiades_places[place]["reprLat"].to_f, @pleiades_places[place]["reprLong"].to_f) < DISTANCE_THRESHOLD)
            puts "#{place},#{way.inspect}"
            return true
          end
        end
        return false
      else
        @check_nodes = (@check_nodes + way.nodes.map{|n| n.to_i}).uniq
      end
      # way.nodes.each do |node|
      #   $stderr.puts @database.get_node(node.to_i)
      # end
      return true
    end

    return false
  end

  def relation(relation)
    if relation.tags['name'] && @pleiades_names.keys.include?(relation.tags['name'])
      $stderr.puts relation.inspect
      return true
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
