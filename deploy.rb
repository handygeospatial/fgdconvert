require 'fileutils'
Dir.glob('output/part*') {|path|
  File.foreach(path) {|l|
    (path, geojsonl) = l.split("\t")
    path = "dst/#{path}"
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') {|w|
      geojson = <<-EOS
{"type": "FeatureCollection", "features": [#{geojsonl}]}
      EOS
      print "#{geojson.size} characters to #{path}\n"
      w.print geojson
    }
  }
}
