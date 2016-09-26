require 'fileutils'
require 'yaml'
require_relative 'utils'

module Bootstrap
  @@base_dir = ''
  @@photo_dirs = []

  def self.do(directory)
    @@base_dir = File.absolute_path directory
    puts "Bootstrapping #{@@base_dir}"

    directories
    hashfile

    @@photo_dirs
  end

  def self.directories
    Dir.chdir(@@base_dir) do
      Dir.glob('*').select { |f| File.directory? f }.reject { |f| f == '_resized' }.each do |d|
        d_slug = Utils.slugify d
        FileUtils.mv d, d_slug unless d == d_slug
        @@photo_dirs << d_slug
        FileUtils.mkdir_p File.join(@@base_dir, '_resized', d_slug)
      end
    end
  end

  def self.hashfile
    h = File.join(@@base_dir, 'Hashfile')

    orig_hashes = File.exists?(h) ? YAML.load(File.read(h)) : {}

    File.open(h, 'w') do |f|
      f.write YAML.dump Hash[@@photo_dirs.map { |d| [d, orig_hashes[d] || '------'] }]
    end
  end
end
