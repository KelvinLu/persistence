module Utils
  def self.slugify(name)
    name.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
  end
end
