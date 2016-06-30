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

    # logger to use, if logger is not set, then messages will not be logged
    attr_accessor :logger

    # Percent of time to check the cache size
    attr_accessor :check_size_percent

    # The maximum number of entries in the cache.
    # Note that since we don't check the cache size every time, the actual size might exceed this number
    attr_accessor :max_cache_size

    # The percent of entries to evict (delete) if size is exceeded
    attr_accessor :evict_percent

    def initialize dir='/tmp/cache', permissions=0666
      # Make sure 'dir' is not a file
      if (File.exist?(dir) && !File.directory?(dir))
        raise "DiskCache dir #{dir} should be a directory."
      end
      @dir = dir
      @permissions = permissions
      @enable_logging = false
      @check_size_percent = 20
      @max_cache_size = 5000
      @evict_percent = 20.0
      mkdir
    end

    def set first_key, second_key='', files=[]
      # TODO: validate inputs

      # If cache exists already, overwrite it.
      content_dir = get first_key, second_key
      second_key_file = nil

      begin
        if (content_dir.nil?)

          # Check the size of cache, and evict entries if too large
          check_cache_size if (rand(100) < check_size_percent)

          # Make sure cache dir doesn't exist already
          first_cache_dir = File.join(dir, first_key)
          if (File.exist?first_cache_dir)
            raise "BuildCache directory #{first_cache_dir} should be a directory" unless File.directory?(first_cache_dir)
          else
            FileUtils.mkpath(first_cache_dir)
          end
          num_second_dirs = Dir[first_cache_dir + '/*'].length
          cache_dir = File.join(first_cache_dir, num_second_dirs.to_s)
          # If cache directory already exists, then a directory must have been evicted here, so we pick another name
          while File.directory?cache_dir
            cache_dir = File.join(first_cache_dir, rand(num_second_dirs).to_s)
          end
          content_dir = File.join(cache_dir, '/content')
          FileUtils.mkpath(content_dir)

          # Create 'last_used' file
          last_used_filename = File.join(cache_dir, 'last_used')
          FileUtils.touch last_used_filename
          FileUtils.chmod(permissions, last_used_filename)

          # Copy second key
          second_key_file = File.open(cache_dir + '/second_key', 'w+')
          second_key_file.flock(File::LOCK_EX)
          second_key_file.write(second_key)

        else
          log "overwriting cache #{content_dir}"

          FileUtils.touch content_dir + '/../last_used'
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
        return content_dir
      rescue => e
        # Something went wrong, like a full disk or some other error.
        # Delete any work so we don't leave cache in corrupted state
        unless content_dir.nil?
          # Delete parent of content directory
          FileUtils.rm_rf(File.expand_path('..', content_dir))
        end
        log "ERROR: Could not set cache entry. #{e.to_s}"
        return 'ERROR: !NOT CACHED!'
      end
      
    end

    # Get the cache directory containing the contents corresponding to the keys
    def get first_key, second_key=''
      # TODO: validate inputs

      begin
        cache_dirs = Dir[File.join(@dir, first_key + '/*')]
        cache_dirs.each do |cache_dir|
          second_key_filename = cache_dir + '/second_key'
          # If second key filename is bad, we skip this directory
          if (!File.exist?(second_key_filename) || File.directory?(second_key_filename))
            next
          end
          second_key_file = File.open(second_key_filename, "r" )
          second_key_file.flock(File::LOCK_SH)
          out = second_key_file.read
          if (second_key.to_s == out)
            FileUtils.touch cache_dir + '/last_used'
            cache_dir = File.join(cache_dir, 'content')
            second_key_file.close
            return cache_dir if File.directory?(cache_dir)
          end
          second_key_file.close
        end
      rescue => e
        log "ERROR: Could not get cache entry. #{e.to_s}"
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
        begin
          cache_dir = get first_key, second_key
          log "cache hit #{cache_dir}"
          mkdir dest_dir
          FileUtils.cp_r(cache_dir + '/.', dest_dir)
          return Dir[cache_dir + '/*'].map { |pathname| File.basename pathname }
        rescue => e
          # Since we don't return, error counts as a cache miss
          log "ERROR: Could not retrieve cache entry contents. #{e.to_s}"
        end
      end

      # If cache miss, run the block and put the results in the cache
      files = yield
      output_files = files.map { |filename| File.join(dest_dir, filename) }
      # Check the cache again in case someone else populated it already
      unless (hit?first_key, second_key)
        cache_dir = set(first_key, second_key, output_files)
        log "cache miss, caching results to #{cache_dir}"
      end
      return files
    end

    def check_cache_size
      log "checking cache size"
      entries = Dir[@dir + '/*/*']
      if entries.length > max_cache_size
        # If cache is locked for maintainance (lock exists and less than 8 hours old), then we skip the check
        lock_filename = File.join(@dir, 'cache_maintenance')
        return if (File.exist?(lock_filename) && (File.mtime(lock_filename) > Time.now - (8 * 60 * 60)))
        FileUtils.touch(lock_filename)

        log "evicting old cache entries"
        # evict some entries
        entries = entries.sort do |a,b|
          # evict entries that don't have a last_used file
          a_file = File.join(a, 'last_used')
          next -1 if !File.exist?a_file
          b_file = File.join(b, 'last_used')
          next 1 if !File.exist?b_file
          next File.mtime(a_file) <=> File.mtime(b_file)
        end

        entries_to_delete = (entries.length * evict_percent / 100).ceil
        entries[0..(entries_to_delete-1)].each { |entry| FileUtils.rm_rf(entry) }
        # Delete empty directories
        Dir[@dir + '/*'].each { |d| Dir.rmdir d if (File.directory?(d) && (Dir.entries(d) - %w[ . .. ]).empty?) }

        # Delete lock file
        FileUtils.rm lock_filename, :force => true
      end
    end
    
    private
      
    def mkdir dir=@dir
      FileUtils.mkpath(dir) unless File.directory?(dir)
    end

    def log message
      unless (@logger.nil?)
        @logger.info { "[BuildCache::DiskCache] #{message.to_s}" }
      end
    end

  end
  
end
