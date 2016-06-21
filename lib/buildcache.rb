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

    # The directory containing cached files
    attr_reader :dir

    # The Linux permissions that cached files should have
    attr_reader :permissions

    def initialize dir='/tmp/cache', permissions=0666
      # Make sure 'dir' is not a file
      if (File.exist?(dir) && !File.directory?(dir))
        raise "DiskCache dir #{dir} should be a directory."
      end
      @dir = dir
      @permissions = permissions
      mkdir
    end

    def set first_key, second_key='', files=[]
      # TODO: validate inputs

      # If cache exists already, overwrite it.
      content_dir = get first_key, second_key
      second_key_file = nil

      if (content_dir.nil?)

        # Make sure cache dir doesn't exist already
        cache_dir = File.join(dir, first_key)
        if (File.exist?cache_dir)
          raise "BuildCache directory #{cache_dir} should be a directory" unless File.directory?(cache_dir)
        else
          FileUtils.mkpath(cache_dir)
        end
        cache_dir = cache_dir + '/' +  Dir[cache_dir + '/*'].length.to_s
        content_dir = File.join(cache_dir, '/content')
        FileUtils.mkpath(content_dir)

        # Copy second key
        second_key_file = File.open(cache_dir + '/second_key', 'w+')
        second_key_file.flock(File::LOCK_EX)
        second_key_file.write(second_key)

      else
        second_key_file = File.open(content_dir + '/../second_key', 'r')
        second_key_file.flock(File::LOCK_EX)
        # Clear any existing files out of cache directory
        FileUtils.rm_rf(content_dir + '/.')
      end

      # Copy files into content_dir
      files.each do |filename|
        FileUtils.cp(filename, content_dir)
      end
      FileUtils.chmod(permissions, Dir[content_dir + '/*'])

      # Release the lock
      second_key_file.close
      
    end

    # Get the cache directory containing the contents corresponding to the keys
    def get first_key, second_key=''
      # TODO: validate inputs

      cache_dirs = Dir[File.join(@dir, first_key + '/*')]
      cache_dirs.each do |cache_dir|
        second_key_filename = cache_dir + '/second_key'
        # If second key file is bad, we skip this directory
        if (!File.exist?(second_key_filename) || File.directory?(second_key_filename))
          next
        end
        second_key_file = File.open(second_key_filename, "r" )
        second_key_file.flock(File::LOCK_SH)
        out = second_key_file.read
        second_key_file.close
        if (second_key.to_s == out)
          cache_dir = File.join(cache_dir, 'content')
          return cache_dir if File.directory?(cache_dir)
        end
      end
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
      # Check the cache again in case someone else populated it already
      unless (hit?first_key, second_key)
        set(first_key, second_key, output_files)
      end
      return files
    end
    
    private
      
    def mkdir
      FileUtils.mkpath(dir) unless File.directory?(dir)
    end

  end
  
end
