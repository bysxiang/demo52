namespace :tool do 

  desc "test1"
  task(:test1) do 
    root = Rails::Paths::Root.new(Rails.root.to_s)

    key = "config/locales"
    root.add(key, { glob: "*.rb" })

    puts "输出expanded"
    p root[key].expanded
  end

  desc "test2"
  task(:test2) do 
    root = Rails::Paths::Root.new(Rails.root.to_s)

    key = "config/locales"
    root.add(key, { with: ["#{key}/x1.yml", "#{key}/test"], glob: "*.rb" })

    puts "输出expanded"
    p root[key].expanded

    puts "输出绝对路径"
    p root[key].absolute_current
  end
end