dict = Hash.new{|h, k| h[k] = []}
%w{source input}.each {|dir|
  Dir.glob("#{dir}/FG-GML*") {|path|
    t = path.split('-')[3]
    dict[dir] << t unless dict[dir].include?(t)
  }
  dict[dir].sort!
}
p dict
p dict["source"] - dict["input"]
