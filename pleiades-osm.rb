#!/usr/bin/env ruby

ENV['OSMLIB_XML_PARSER']='Expat'
require 'OSM/StreamParser'
require 'OSM/Database'
require 'csv'

class PleiadesCallbacks < OSM::Callbacks
  attr_accessor :check_nodes, :database, :reparse, :check_names

  def node(node)
    if reparse
      if @check_nodes.include?(node.id)
        $stderr.puts node.inspect
        return true
      else
        if node.tags['name'] && @check_names.include?(node.tags['name'])
          $stderr.puts node.inspect
          return true
        end
      end
    end
    return false
  end

  def way(way)
    if way.tags['name'] && @check_names.include?(way.tags['name'])
      $stderr.puts way.inspect
      unless reparse
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
    if relation.tags['name'] && @check_names.include?(relation.tags['name'])
      $stderr.puts relation.inspect
      return true
    end

    return false
  end

  def initialize(db, names)
    @check_nodes = []
    @database = db
    @reparse = false
    @check_names = names
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
cb = PleiadesCallbacks.new(db, place_names.keys)
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
