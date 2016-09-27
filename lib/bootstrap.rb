require 'fileutils'
require 'yaml'
require 'json'
require_relative 'utils'

module Bootstrap
  @@base_dir = ''
  @@photo_dirs = []

  def self.do(directory, clean=false)
    @@base_dir = File.absolute_path directory
    puts "Bootstrapping #{@@base_dir}"

    assets
    directories
    hashfile clean

    @@photo_dirs
  end

  def self.assets
    ['gallery.css', 'index.css'].each do |f|
      `cp #{f} #{@@base_dir}`
    end
  end

  def self.directories
    Dir.chdir(@@base_dir) do
        Dir.glob('*').select { |f| File.directory? f }.reject { |f| f.end_with? '~resized' }.each do |d|
        d_slug = Utils.slugify d
        FileUtils.mv d, d_slug unless d == d_slug
        @@photo_dirs << d_slug

        FileUtils.mkdir_p File.join(@@base_dir, d_slug + '~resized')
        File.write(File.join(@@base_dir, d_slug + '.metadata'), JSON.generate({
          title: d_slug,
          description: 'This gallery has no description... how boring.'
        })) unless File.exists? File.join(@@base_dir, d_slug + '.metadata')
      end

      File.write(File.join(@@base_dir, 'index.metadata'), JSON.generate({
        title: 'My cool photoblog',
        photo_dirs: @@photo_dirs
      })) unless File.exists? File.join(@@base_dir, 'index.metadata')
    end
  end

  def self.hashfile(clean=false)
    h = File.join(@@base_dir, 'Hashfile')

    orig_hashes = {}
    orig_hashes = YAML.load File.read h if (File.exists?(h) and not clean)

    File.open(h, 'w') do |f|
      f.write(YAML.dump Hash[@@photo_dirs.map { |d| [d, orig_hashes[d] || '------'] }])
    end
  end
end
