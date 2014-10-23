#!/usr/bin/env ruby
require 'fileutils'
require 'json'

last = nil
geojsonl = nil

def write(geojsonl, path)
  print "#{path}\t#{JSON.dump(geojsonl)[1..-2]}\n"
end

while gets
  r = $_.strip.split("\t")
  current = r[0]
  if current != last
    write(geojsonl, last) unless last.nil?
    geojsonl = []
  end
  geojsonl << JSON.parse(r[1])
  last = current
end
write(geojsonl, last)
