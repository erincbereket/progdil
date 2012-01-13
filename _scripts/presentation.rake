
require 'pathname'	#ihtiyacimiz lan pathname,pythonconfig,yaml modülleri  çağrılmıştır.
require 'pythonconfig'	#require kodun bir kere ve ihtiyaç duyulduğu zaman yüklenmesini sağlar.
require 'yaml'

CONFIG = Config.fetch('presentation', {}) 	#Config.fetch ile ilk argümandaki keye göre veriyi alır ve döndürür.

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')	#İlk olarak sunumlara ait bölüm alınıp sunum dizini oluşturulur.
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')	#Herhangi bir duruma karşılık ilklendirme yapılır.	
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')		#İndeks dosyasına sunum indeksleri ekleniyor.
IMAGE_GEOMETRY = [ 733, 550 ]					#Belirli bir standart oluşturmak için resim boyutu belirleniyor.Bağımlılıklar belirleniyor.			
DEPEND_KEYS    = %w(source css js)
DEPEND_ALWAYS  = %w(media)i
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',				#Amaçlanan görevler açıklamalarıyla birlikte belirtiliyor.
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {}					#Sunum ve etiket bigileri tutan  presentation ve tag isimli liste oluşturuluyor. 
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)			#Dosya sınıfı oluşturuluyor ve sunum için yeni bir yol açılıyor.
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end									#Tanımlanan fonksiyonlarla oluşturulan bu yollara erişim sağlandı.Mutlak yol göreceli yol haline getirildi.
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :	#Verilen yollar sıralanıyor.
      [path]
  end
end

def png_comment(file, string)					#png_comment isimli bir fonksiyon çağrılıyor ve chunky_png,oily_png resim modülleri  yükleniyor.
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)		#image değişkeniyle temsil edilen resim bir dosyadan aktarılıyor ve üzerinde yapılan değişiklikler kaydediliyor.
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)			#png_optim fonksiyonu oluşturuluyor ve eğer dosyanın boyutu belirtilenden küçükse fonksiyona döndürülüyor.
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)					#Eğer dosya var ve aynı isimli  ise dosyaya yeni isim verilir ve çıkış silinir.
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end

def jpg_optim(file)					#jpg_optim fonksiyonu sh ile belirtilmiş satırları konsoldan çalıştırıyor.jpg dosyalarını optimize ediyor.
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]
									#optim fonksiyonu ile uzantıları png,jpg,jpeg olan dosyalar değişkenlere atılıyor.
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }	
  end									#optimize edilmiş olanları alıyor.

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }	
    size, i = [w, h].each_with_index.max					#png ve jpgs için boyut düzenlemesi yapılıyor.
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end
	
  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|					#Optimize edilmiş resimleri kullanan dosyalar için tekrar üretilmesi sağlanıyor.
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end							
  end
end




default_conffile = File.expand_path(DEFAULT_CONFFILE)			#Oluşturulan mutlak dosya yolu sayesinde alt dizinlere erişiliyor.

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)				#
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']				#landslide bölümü tanımlanmamışsa ekrana hata çıktısını basıyor.
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end

    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md')			#index.md isimli dosya var ise durum açık gösteriliyor
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md')	#presentation.md isimli dosya var ise durum kapalı gösterliyor.
      base = 'presentation'
      ispublic = false
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"	#Başka durumlarda hata çıktısı üretiliyor.
      exit 1
    end

    basename = base + '.html'			#tanımlanan md dosyalarına html ekleniyor.
    thumbnail = File.to_herepath(base + '.png')	#png dosyası ekleniyor.
    target = File.to_herepath(basename)

    deps = []					#deps isminde bir liste oluşturuluyor ve içinde bir takım işlemler yapılıyor oluşturulan target thumbnail dosyaları siliniyor.
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v|		#presentation sunum dosyası için etiketler oluşturuluyor
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten] #görev sekmesi oluşturulupgörev haritası yapılıyor.

presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|			#isim uzayından sunum alınıyor.
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do		#resimler gönderiliyor.
      next unless data[:public]
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +		#internette gönderilecek web adresi alınıyor.
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +					#resimlerin boyutları düzenleniyor.
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"		#yeniden boyutlandırılıyor.
      png_optim(data[:thumbnail])
    end

    task :optim do			#optim görevi yapılıyor.
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]	#index görevi veriye uygulanıyor.

    task :build => [:optim, data[:target], :index]	#build görevi veriye uygulanıyor.

    task :view do				#view görevi yapılıyor dosyaların olup olmama durumuna göre dosyalar oluşturuluyor.
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view]	#run görevi için build ve view görevleri çalıştırılıyor.

    task :clean do
      rm_f data[:target]		#clean görevi ile sonradan oluşturulan resimler siliniyor.
      rm_f data[:thumbnail]
    end

    task :default => :build		#default görevi ile build görevi çalıştırılıyor.
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]			#görev haritasına görev isimleri ekleniyor.
    tasktab[name][:tasks] << t
  end
end

namespace :p do					#isim uzayındaki görev sekmelerinde bulunan görevlerin isim ve bilgileri alınıyor.
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]			#görev isim ve bilgileri tanımlanıyor.
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {}	#build görevinde INDEX_FILE dosyası yükleniyor.
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|		#Bu dosya yazılabilir olarak açılıyor ve içine index.to_yaml dosyası yazılıyor.
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
  task :menu do				#menü göreviyle sunum görevleri sıralanıyor.
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end					#
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|			#menü ile bazı seçimler yapılıyor.
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline		#sunumun rengi ve özelliği seçiliyor.
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke		#rake ediliyor.

  end
  task :m => :menu					# m görevi için menü çalıştırılıyor.
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
