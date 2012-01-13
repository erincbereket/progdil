require 'yaml'
require 'erb'

task :exam do
  Dir.foreach("_exams") do |dosya|
    unless (dosya == "." or dosya == "..")
      sp = YAML.load_file("_exams/" + dosya)
      title = sp['title']
      footer = sp['footer']
      q = sp['q']
      liste = []
      t = 0
      for i in q
        oku  = File.read("_includes/q/" + i)
        liste[t] = oku
        t = +1
      end
      yeni = ERB.new(File.read("_templates/exam.md.erb")).result(binding)
      f = File.open('yeni.md', 'w')
      f.write(yeni)
      f.close()
      sh "markdown2pdf yeni.md -o _includes/#{dosya}"
      sh "rm -f yeni.md"
    end
  end
end

task :clean do
  Dir.foreach("_includes/") do |haric|
    unless (haric == "." or haric == "..")
      sh "rm -f _includes/#{haric}"
    end
  end
end

task :default => :exam


