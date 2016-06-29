#!/usr/bin/env ruby

ENV['OSMLIB_XML_PARSER']='Expat'
require 'OSM/StreamParser'
require 'OSM/Database'

class PleiadesCallbacks < OSM::Callbacks
  attr_accessor :check_nodes, :database, :reparse, :name_string

  def node(node)
    if reparse
      if @check_nodes.include?(node.id)
        $stderr.puts node.inspect
        return true
      else
        if node.tags['name'] =~ /#{@name_string}/i
          $stderr.puts node.inspect
          return true
        end
      end
    end
    return false
  end

  def way(way)
    if way.tags['name'] =~ /#{@name_string}/i
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
    if relation.tags['name'] =~ /#{@name_string}/i
      $stderr.puts relation.inspect
      return true
    end

    return false
  end

  def initialize(db, name)
    @check_nodes = []
    @database = db
    @reparse = false
    @name_string = name
  end
end

osm_file = ARGV[0]
name_string = ARGV[1]

db = OSM::Database.new
cb = PleiadesCallbacks.new(db, name_string)
parser = OSM::StreamParser.new(:filename => osm_file, :callbacks => cb)
$stderr.puts "Parsing..."
parser.parse
$stderr.puts cb.check_nodes.inspect
$stderr.puts "Re-parsing..."
cb.reparse = true
parser = OSM::StreamParser.new(:filename => osm_file, :callbacks => cb, :db => db)
parser.parse
$stderr.puts "#{db.nodes.keys.length} nodes"
$stderr.puts "#{db.ways.keys.length} ways"
$stderr.puts "#{db.relations.keys.length} relations"
db.clear
