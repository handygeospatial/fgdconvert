# coding: utf-8
require 'find'
require 'json'
require 'zlib'
require 'nokogiri'
require 'georuby-ext'
require 'geo_ruby/geojson'
require 'zip' # gem install rubyzip

# Meshcode is probably Japanese English.
module Meshcode
  def self.width(code)
    case code.size
    when 8
      45.0 / 60 / 60
    else
      raise 'not implemented.'
    end
  end

  def self.height(code)
    case code.size
    when 8
      30.0 / 60 / 60
    else
      raise 'not implemented.'
    end
  end

  def self.lefttop(code)
    case code.size
    when 6
      [(code[2..3].to_f + code[5].to_f / 8) + 100, 
       (code[0..1].to_f + (code[4].to_f + 1) / 8) * 2 / 3]
    when 8
      [(code[2..3].to_f + code[5].to_f / 8 + code[7].to_f/ 80) + 100, 
       (code[0..1].to_f + code[4].to_f / 8 + (code[6].to_f + 1) / 80) * 2 / 3]
    else
      raise 'not implemented.'
    end
  end
end

module Math
  def self.sec(x)
    1.0 / cos(x)
  end
end

module XYZ
  def self.pt2xy(pt, z)
    lnglat2xy(pt.x, pt.y, z)
  end

  def self.lnglat2xy(lng, lat, z)
    n = 2 ** z
    rad = lat * 2 * Math::PI / 360
    [n * ((lng + 180) / 360),
      n * (1 - (Math::log(Math::tan(rad) +
        Math::sec(rad)) / Math::PI)) / 2]
  end

  def self.xyz2lnglat(x, y, z)
    n = 2 ** z
    rad = Math::atan(Math.sinh(Math::PI * (1 - 2.0 * y / n)))
    [360.0 * x / n - 180.0, rad * 180.0 / Math::PI]
  end

  def self.xyz2envelope(x, y, z)
    GeoRuby::SimpleFeatures::Envelope.from_points([
      GeoRuby::SimpleFeatures::Point.from_coordinates(
        xyz2lnglat(x, y, z)),
      GeoRuby::SimpleFeatures::Point.from_coordinates(
        xyz2lnglat(x + 1, y + 1, z))])
  end
end

class GeoRuby::SimpleFeatures::Geometry
  def tile(z)
    lower = XYZ::pt2xy(self.bounding_box[0], z)
    upper = XYZ::pt2xy(self.bounding_box[1], z)
    rg = self.to_rgeo
    lower[0].truncate.upto(upper[0].truncate) {|x|
      upper[1].truncate.upto(lower[1].truncate) {|y|
        env = XYZ::xyz2envelope(x, y, z).to_rgeo
        intersection = rg.intersection(env)
        if intersection.is_empty?
          next
        end
        if intersection.respond_to?(:each)
          intersection.each {|g|
            yield "#{z}/#{x}/#{y}.geojson", g.to_georuby
          }
        else
          yield "#{z}/#{x}/#{y}.geojson", intersection.to_georuby
        end
      }
    }
  end
end

# Probably wrong implementation because georeferencing relies on 
# filenames = 'mesh code'
class DEM
  def parse(params)
    (left, top) = Meshcode::lefttop(params[:meshcode])
    skip = true
    count = 0
    params[:stream].foreach {|l|
      if l.include?('<gml:tupleList>')
        skip = false
        next
      elsif l.include?('</gml:tupleList>')
        skip = true
        next
      elsif !skip
        (i, j) = [count % @n_lng, count / @n_lng]
        lng = left + @d_lng * (i + 0.5)
        lat = top - @d_lat * (j + 0.5)
        x, y = XYZ::lnglat2xy(lng, lat, params[:z])
        x = x.to_i
        y = y.to_i
        (type, height) = l.encode('UTF-8').strip.split(',')
        next unless type
        f = {:type => 'Feature', 
          :geometry => {:type => 'Point', :coordinates => [lng, lat]},
          :properties => {
            :type => type, :height => height.to_f,
            :datePublished => params[:datePublished]
        }}
        params[:ost].print "#{params[:z]}/#{x}/#{y}.geojson\t#{JSON::dump(f)}\n"
        count += 1
      end
    }
  end
end

class DEM5A < DEM
  def initialize
    @n_lng = 225
    @n_lat = 150
    @d_lng = 1.0 / 80 / @n_lng
    @d_lat = 2.0 / 3 / 80 / @n_lat
  end
end

class DEM5B < DEM
  def initialize
    @n_lng = 225
    @n_lat = 150
    @d_lng = 1.0 / 80 / @n_lng
    @d_lat = 2.0 / 3 / 80 / @n_lat
  end
end

class DEM10B < DEM
  def initialize
    @n_lng = 1125
    @n_lat = 750
    @d_lng = 1.0 / 8 / @n_lng
    @d_lat = 2.0 / 3 / 8 / @n_lat
  end
end

class DEM10A < DEM
  def initialize
    @n_lng = 1125
    @n_lat = 750
    @d_lng = 1.0 / 8 / @n_lng
    @d_lat = 2.0 / 3 / 8 / @n_lat
  end
end

class PolygonFeature
  CLASSES = %w{AdmArea BldA WA WStrA}
  SKIPS = %w{gml:timePosition gml:posList gml:LineStringSegment gml:segments gml:Curve gml:curveMember gml:Ring}
  def initialize
    @sax_document = Nokogiri::XML::SAX::Document.new
    class << @sax_document
      def set_params(params)
        @params = params
      end
      def start_document
        @buf = ''
      end
      def start_element(name, attrs)
        if CLASSES.include?(name)
          @geojsonl = {
            :type => 'Feature',
            :geometry => {:type => 'Polygon', :coordinates => []},
            :properties => {
              :class => name,
              :datePublished => @params[:datePublished]
            }
          }
        end
      end
      def characters(s)
        @buf += s
      end
      def end_element(name)
        if CLASSES.include?(name)
          begin
            g = GeoRuby::SimpleFeatures::Polygon.from_coordinates(@coordinates)
            g.tile(@params[:z]) {|path, g_|
              next unless g_.class == GeoRuby::SimpleFeatures::Polygon
              @geojsonl[:geometry] = JSON::parse(g_.as_geojson)
              @params[:ost].print "#{path}\t#{JSON::generate(@geojsonl)}\n"
            }
          rescue
            $stderr.print $!, "\n"
          end
        else
          case name
          when 'type', 'fid', 'vis', 'admOffice', 'devDate', 'lfSpanFr', 'name', 'admCode'
            @geojsonl[:properties][name.to_sym] = @buf.strip
          when 'alti'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_f
          when 'orgGILvl'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_i
          when 'gml:exterior'
            @coordinates = [[]]
            @buf.strip.split("\n").each {|s|
              @coordinates[0] << s.split(' ').reverse.map{|v| v.to_f}
            }
          when 'gml:interior'
            ring = []
            @buf.strip.split("\n").each {|s|
              ring << s.split(' ').reverse.map{|v| v.to_f}
            }
            @coordinates << ring
          else
            #print "*** #{name}: #{@buf}\n" unless SKIPS.include?(name)
          end
        end
        @buf = '' unless SKIPS.include?(name)
      end
    end
    @sax_parser = Nokogiri::XML::SAX::Parser.new(@sax_document)
  end

  def parse(params)
    @sax_document.set_params(params)
    @sax_parser.parse(params[:stream])
  end
end

class LineStringFeature
  CLASSES = %w{BldL Cntr RdEdg WL Cstline AdmBdry RailCL RdCompt CommBdry WStrL SBBdry}
  def initialize
    @sax_document = Nokogiri::XML::SAX::Document.new
    class << @sax_document
      def set_params(params)
         @params = params
      end
      def start_document
        @buf = ''
      end
      def start_element(name, attrs)
        if CLASSES.include?(name)
          @geojsonl = {
            :type => 'Feature',
            :geometry => {:type => 'LineString', :coordinates => []},
            :properties => {
              :class => name,
              :datePublished => @params[:datePublished]
            }
          }
        end
      end
      def characters(s)
        @buf += s
      end
      def end_element(name)
        if CLASSES.include?(name)
          begin
            g = GeoRuby::SimpleFeatures::LineString.from_coordinates(@coordinates)
            g.tile(@params[:z]) {|path, g_|
              next unless g_.class == GeoRuby::SimpleFeatures::LineString
              @geojsonl[:geometry] = JSON::parse(g_.as_geojson)
              @params[:ost].print "#{path}\t#{JSON::generate(@geojsonl)}\n"
            }
          rescue
            $stderr.print $!, "\n"
          end
        else
          case name
          when 'type', 'fid', 'vis', 'admOffice', 'devDate', 'lfSpanFr'
            @geojsonl[:properties][name.to_sym] = @buf.strip
          when 'alti'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_f
          when 'orgGILvl'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_i
          when 'gml:posList'
            @coordinates = []
            @buf.strip.split("\n").each {|s|
              @coordinates << s.split(' ').reverse.map{|v| v.to_f}
            }
          else
            # print "*** #{name}: #{@buf}\n" unless name == 'gml:timePosition'
          end
        end
        @buf = '' unless name == 'gml:timePosition'
      end
    end
    @sax_parser = Nokogiri::XML::SAX::Parser.new(@sax_document)
  end

  def parse(params)
    @sax_document.set_params(params)
    @sax_parser.parse(params[:stream])
  end
end

class PointFeature
  CLASSES = %w{AdmPt CommPt ElevPt GCP SBAPt}
  def initialize
    @sax_document = Nokogiri::XML::SAX::Document.new
    class << @sax_document
      def set_params(params)
         @params = params
      end
      def start_document
        @buf = ''
      end
      def start_element(name, attrs)
        if CLASSES.include?(name)
          @geojsonl = {
            :type => 'Feature',
            :geometry => {:type => 'Point', :coordinates => []},
            :properties => {
              :class => name,
              :datePublished => @params[:datePublished]
            }
          }
        end
      end
      def characters(s)
        @buf += s
      end
      def end_element(name)
        if CLASSES.include?(name)
          x, y = XYZ::lnglat2xy(@lng, @lat, @params[:z])
          x = x.to_i
          y = y.to_i
          path = "#{@params[:z]}/#{x}/#{y}.geojson"
          @params[:ost].print "#{path}\t#{JSON::generate(@geojsonl)}\n"
        else
          case name
          when 'type', 'fid', 'vis', 'admOffice', 'devDate', 'lfSpanFr', 'orgName', 'gcpClass', 'gcpCode', 'name'
            @geojsonl[:properties][name.to_sym] = @buf.strip
          when 'alti', 'B', 'L'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_f
          when 'orgGILvl', 'altiAcc', 'sbaNo'
            @geojsonl[:properties][name.to_sym] = @buf.strip.to_i
          when 'gml:pos'
            @lat, @lng = @buf.strip.split(" ").map{|v| v.to_f}
            @geojsonl[:geometry][:coordinates] = [@lng, @lat]
          else
            # print "*** #{name}: #{@buf}\n" unless name == 'gml:timePosition'
          end
        end
        @buf = '' unless name == 'gml:timePosition'
      end
    end
    @sax_parser = Nokogiri::XML::SAX::Parser.new(@sax_document)
  end

  def parse(params)
    @sax_document.set_params(params)
    @sax_parser.parse(params[:stream])
  end
end

Find.find('(your fgd directory)') {|path|
  next unless /(5439|5440|5638|5639)\d\d-ALL/.match path
  $stderr.print "Processing #{File.basename(path)}.\n"
  dst_path = "input/#{File.basename(path).sub('zip', 'geojson.gz')}"
  if File.exist?(dst_path) 
    $stderr.print " #{dst_path} already exists.\n"
    next
  end
  tmp_path = 'a.geojson.gz'
  File.open(tmp_path, 'w') {|w|
    Zlib::GzipWriter.wrap(w) {|gz|
      Zip::File.open(path) {|zip|
        zip.each {|entry|
          next unless /xml$/.match entry.name
          $stderr.print(" Processing #{entry.name}\n")
          r = File.basename(entry.name, '.xml').split('-')
          r.pop if r[-1].size == 4
          next unless r.shift == 'FG'
          next unless r.shift == 'GML'
          datePublished = r.pop.insert(4, '-').insert(7, '-')
          type = r.pop
          meshcode = r.join
          params = {:path => entry.name, :type => type, 
            :meshcode => meshcode, :z => 18, :stream => entry.get_input_stream,
            :ost => gz, :datePublished => datePublished}
          if LineStringFeature::CLASSES.include?(type)
            LineStringFeature.new.parse(params)
          elsif PointFeature::CLASSES.include?(type)
            PointFeature.new.parse(params)
          elsif PolygonFeature::CLASSES.include?(type)
            PolygonFeature.new.parse(params)
          else
            case type
            when 'DEM5A', 'DEM5B'
              Kernel.const_get(type).new.parse(params)
            when 'dem10a', 'dem10b'
              Kernel.const_get(type.upcase).new.parse(params)
            else
              # print "converter for #{type} not implemented.\n"
            end
          end
        }
      }
    }
  }
  FileUtils.mv(tmp_path, dst_path)
}
