task :default do
  require 'find'
  sh "rm -r output" if File.directory?('output')
  Find.find('source') {|path|
    next unless /(BldL|Cntr|RdEdg|WL|Cstline|AdmBdry|RailCL|RdCompt|CommBdry|WStrL|SBBdry|AdmPt|CommPt|ElevPt|GCP|SBAPt|AdmArea|BldA|WA|WStrA)/.match path
#    next unless /(AdmArea|BldA|WA|WStrA)/.match path
    input_path = "#{path.sub('source', 'input').sub('xml', 'geojsonl')}"
    next if File.exist?(input_path)
    sh "gunzip #{path}; ruby convert.rb #{path.sub('.gz', '')} | gzip -c > #{input_path}; gzip #{path.sub('.gz', '')}"
  }
  sh "hadoop jar /usr/local/Cellar/hadoop/2.5.1/libexec/share/hadoop/tools/lib/hadoop-streaming-2.5.1.jar -input input -output output -mapper cat -reducer reduce.rb"
  sh "rm -r dst" if File.directory?('dst')
  sh "mkdir dst"
  sh "ruby deploy.rb"
end
