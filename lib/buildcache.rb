require 'buildcache/version'
require 'digest'

module BuildCache

  def self.key_gen files=[], metadata={}
    # TODO: Validate inputs.
    flat_sig = ''
    unless files.empty?
      files.each { |file|
        flat_sig << Digest::MD5.file(file).hexdigest
      }
    end
    unless metadata.empty?
      metadata.each do |key, value|
        flat_sig << Digest::MD5.hexdigest(key)
        flat_sig << Digest::MD5.hexdigest(value)
      end
    end
    return Digest::MD5.hexdigest(flat_sig)
  end

  class DiskCache

    attr_reader :dir

    def initialize dir='/tmp/cache'
      # TODO: Make sure 'dir' is not a file
      @dir = dir
      mkdir
    end

    def set first_key, second_key='', files=[]
      # TODO: validate inputs
      # Make sure cache dir doesn't exist already
      cache_dir = File.join(dir, first_key + '/0/content')
      raise "BuildCache directory #{cache_dir} already exists" if File.directory?(cache_dir)
      FileUtils.mkpath(cache_dir)

      # Copy files into cache_dir
      files.each do |filename|
        FileUtils.cp(filename, cache_dir)
      end
      
    end

    # Get the cache directory containing the contents corresponding to the keys
    def get first_key, second_key=''
      # TODO: validate inputs
      # TODO: Consider second_key
      cache_dir = File.join(dir, first_key + '/0/content')
      return cache_dir if File.directory?(cache_dir)
      return nil
    end

    def hit? first_key, second_key=''
      return get(first_key, second_key) != nil
    end
    
    private
      
    def mkdir
      FileUtils.mkpath(dir) unless File.directory?(dir)
    end

  end
  
end
