task :default do
  sh "rm -r output" if File.directory?('output')
  sh "ruby convert.rb"
  sh "hadoop jar /usr/local/Cellar/hadoop/2.5.1/libexec/share/hadoop/tools/lib/hadoop-streaming-2.5.1.jar -input input -output output -mapper cat -reducer reduce.rb"
  sh "rm -r dst" if File.directory?('dst')
  sh "mkdir dst"
  sh "ruby deploy.rb"
end
