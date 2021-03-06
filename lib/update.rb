require 'fileutils'
require 'pathname'
require 'yaml'
require 'json'
require 'mini_magick'
require 'erb'
require 'ostruct'

module Update
  @@base_dir = ''
  @@photo_dirs = []

  def self.do(directory, photo_dirs, commands={})
    @@base_dir = File.absolute_path directory
    @@photo_dirs = photo_dirs

    @@gallery_erb = ERB.new File.read 'gallery.html.erb'
    @@index_erb = ERB.new File.read 'index.html.erb'

    check commands
  end

  def self.check(commands={})
    orig_hashes = YAML.load File.read File.join(@@base_dir, 'Hashfile')
    tree_hashes = Hash[(`cd #{@@base_dir} && git ls-tree HEAD`.split "\n")
      .map { |o| o.split[1, 3] }
      .select { |o| o[0] == 'tree' }
      .map { |o| [o[2], o[1][0, 6]] }
    ]

    changed_dirs = []
    orig_hashes.each do |photo_dir, dir_hash|
      tree_hash = tree_hashes[photo_dir]
      changed_dirs << photo_dir if tree_hash and dir_hash != tree_hash
    end

    changed_dirs.each do |photo_dir|
      orig_hashes[photo_dir] = tree_hashes[photo_dir]
      blob_hashes = Hash[(`cd #{File.join(@@base_dir, photo_dir)} && git ls-tree HEAD`.split "\n")
        .map { |o| o.split[1, 3] }
        .select { |o| o[0] == 'blob' }
        .map { |o| [o[2], o[1][0, 32]] }
      ]
      generate_manifest photo_dir, blob_hashes
      generate_resize photo_dir, blob_hashes if commands[:resize]
      generate_gallery photo_dir if commands[:galleries]
    end

    generate_index if commands[:index]

    File.write(File.join(@@base_dir, 'Hashfile'), YAML.dump(orig_hashes))
  end

  def self.generate_manifest(photo_dir, blob_hashes)
    puts "~ manifest #{photo_dir}"

    m = File.join(@@base_dir, "#{photo_dir}.manifest")
    File.write(m, '[]') unless File.exists? m
    manifest = JSON.parse File.read m

    manifest_photos = manifest.map { |o| o['basename'] }
    dir_photos = (Dir.glob File.join(@@base_dir, photo_dir, '*')).map { |f| File.basename f }
    remove_photos = manifest_photos - dir_photos
    append_photos = dir_photos - manifest_photos
    existing_photos = manifest_photos & dir_photos

    remove_photos.each do |f|
      puts '  - ' + f
      manifest.delete_if { |o| o['basename'] == f }
    end
    append_photos.each do |f|
      puts '  + ' + f

      raise Exception, "#{f} has no Git blob (are the changes for #{photo_dir} committed?)" unless blob_hashes[f]

      manifest.unshift({
        basename: f,
        filename: File.join('/', photo_dir, f),
        hash: blob_hashes[f],
        resized: File.join('/', photo_dir + '~resized', blob_hashes[f] + File.extname(f))
      })
    end
    manifest.each do |o|
      f = o['basename']
      if existing_photos.include? f and o['hash'] != blob_hashes[f]
        puts '  ~ ' + f
        o['hash'] = blob_hashes[f]
      end
    end

    File.write(m, JSON.pretty_generate(manifest))
  end

  def self.generate_resize(photo_dir, blob_hashes)
    puts "~ resized #{photo_dir}"

    resizes = Dir.glob(File.join(@@base_dir, photo_dir + '~resized', '*')).map { |f| File.basename f }
    resizes = Hash[resizes.map { |f| [f, File.basename(f, '.*')] }]
    photos = Dir.glob(File.join(@@base_dir, photo_dir, '*')).map { |f| File.basename f }
    photos = Hash[photos.map { |f| [f, blob_hashes[f]] }]

    resizes.each do |r, h|
      if not blob_hashes.has_value? h
        puts "  - #{r}"
        FileUtils.rm File.join(@@base_dir, photo_dir + '~resized', r)
      end
    end

    photos.each do |p, h|
      if not resizes.has_value? h
        puts "  + #{p} -> #{h}"
        image = MiniMagick::Image.open(File.join(@@base_dir, photo_dir, p))
        image.combine_options do |i|
          i.resize '600x600>'
          i.write File.join(@@base_dir, photo_dir + '~resized', h + File.extname(p))
        end
      end
    end
  end

  def self.generate_gallery(photo_dir)
    puts "~ gallery #{photo_dir}"

    render = {
      metadata: JSON.parse(File.read(File.join(@@base_dir, photo_dir + '.metadata'))),
      manifest: JSON.parse(File.read(File.join(@@base_dir, photo_dir + '.manifest')))
    }

    rendered = RenderHash.new(render).render(@@gallery_erb)
    File.write(File.join(@@base_dir, "#{photo_dir}.html"), rendered)
  end

  def self.generate_index
    puts "~ index"

    render = {
        metadata: JSON.parse(File.read(File.join(@@base_dir, 'index.metadata'))),
    }

    render[:metadata]['photo_dirs'].map! do |photo_dir|
        photo_dir_metadata = JSON.parse(File.read(File.join(@@base_dir, photo_dir + '.metadata')))
        photo_dir_manifest = JSON.parse(File.read(File.join(@@base_dir, photo_dir + '.manifest')))

        {
            'name' => photo_dir,
            'title' => photo_dir_metadata['title'],
            'description' => photo_dir_metadata['description'],
            'count' => photo_dir_manifest.count,
            'manifest' => photo_dir_manifest,
            'cover_num' => photo_dir_metadata['cover_num']
        }
    end

    rendered = RenderHash.new(render).render(@@index_erb)
    File.write(File.join(@@base_dir, "index.html"), rendered)
  end
end

class RenderHash < OpenStruct
  def render(template)
    template.result(binding)
  end
end
