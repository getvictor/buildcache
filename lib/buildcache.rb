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
      flat_sig << Digest::MD5.hexdigest(metadata.to_s)
    end
    return Digest::MD5.hexdigest(flat_sig)
  end

  class DiskCache

    attr_reader :dir
    attr_reader :permissions

    def initialize dir='/tmp/cache', permissions=0666
      # TODO: Make sure 'dir' is not a file
      @dir = dir
      @permissions = permissions
      mkdir
    end

    def set first_key, second_key='', files=[]
      # TODO: validate inputs
      # Make sure cache dir doesn't exist already
      cache_dir = File.join(dir, first_key + '/0')
      raise "BuildCache directory #{cache_dir} already exists" if File.directory?(cache_dir)
      content_dir = File.join(cache_dir, '/content')
      FileUtils.mkpath(content_dir)

      # Copy second key
      second_key_file = File.open(cache_dir + '/second_key', 'w+')
      second_key_file.flock(File::LOCK_EX)
      second_key_file.write(second_key)
      second_key_file.close

      # Copy files into content_dir
      files.each do |filename|
        FileUtils.cp(filename, content_dir)
      end
      FileUtils.chmod(permissions, Dir[content_dir + '/*'])
      
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

    def cache input_files, metadata, dest_dir
      # Create the cache keys
      first_key = BuildCache.key_gen input_files, metadata
      second_key = metadata.to_s

      # If cache hit, copy the files to the dest_dir
      if (hit?first_key, second_key)
        cache_dir = get first_key, second_key
        FileUtils.cp_r(cache_dir + '/.', dest_dir)
        return Dir[cache_dir + '/*'].map { |pathname| File.basename pathname }
      end

      # If cache miss, run the block and put the results in the cache
      files = yield
      output_files = files.map { |filename| File.join(dest_dir, filename) }
      set(first_key, second_key, output_files)
      return files
    end
    
    private
      
    def mkdir
      FileUtils.mkpath(dir) unless File.directory?(dir)
    end

  end
  
end
