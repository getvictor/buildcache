require 'spec_helper'
require 'logger'

describe BuildCache do
  it 'has a version number' do
    expect(BuildCache::VERSION).not_to be nil
  end

  describe 'key_gen' do
    it 'should generate key from 1 file' do
      expect(BuildCache.key_gen([$sample_file1])).to eq('ac399640ddcd40089c09307c48ea7447')
    end
    it 'should generate key from 2 files' do
      expect(BuildCache.key_gen([$sample_file1, $sample_file2])).to eq('9a09c27e1f67ede7fbc766fdbea1433c')
    end
  end

  describe BuildCache::DiskCache do
    before(:all) do
      @logger = Logger.new(STDOUT)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "      #{msg}\n"
      end
    end
    describe 'init' do
      it 'should init' do
        expect { BuildCache::DiskCache.new }.to_not raise_error
      end
      it 'should init with correct "dir"' do
        expect { @cache = BuildCache::DiskCache.new($disk_cache_dir) }.to_not raise_error
        expect(@cache.dir).to eq $disk_cache_dir
      end
    end
    describe 'cache one file' do
      before(:all) do
        @instance = BuildCache::DiskCache.new($disk_cache_dir)
        @first_key = BuildCache.key_gen([$sample_file1])
      end
      it 'should not be cached' do
        expect(@instance.hit? @first_key).to be false
        expect(@instance.get @first_key).to be_nil
      end
      it 'should cache file' do
        @instance.set(@first_key, nil, [$sample_file1])
        expect(@instance.hit? @first_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file1))).to be true
      end
      it 'should cache file with same first_key' do
        second_key = 'something_unique'
        @instance.set(@first_key, second_key, [$sample_file2])
        expect(@instance.hit? @first_key, second_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/1/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key, second_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file2))).to be true
      end
      it 'should overwrite cached file' do
        second_key = 'something_unique'
        @instance.logger = @logger
        @instance.set(@first_key, second_key, [$sample_file1])
        expect(@instance.hit? @first_key, second_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/1/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key, second_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file1))).to be true
        expect(File.exists?File.join(result_dir, File.basename($sample_file2))).to be false
      end
      it 'should cache file when first_key subdirectories don\'t exist' do
        FileUtils.rm_rf(Dir[File.join($disk_cache_dir, @first_key, '*')])
        expect(@instance.hit? @first_key).to be false
        @instance.set(@first_key, nil, [$sample_file1])
        expect(@instance.hit? @first_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file1))).to be true
      end
      it 'should miss if valid not present' do
        @instance.set(@first_key, nil, [$sample_file1])
        expect(@instance.hit? @first_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        # Remove 'valid' and check again
        FileUtils.rm(result_dir + '/../valid')
        expect(@instance.hit? @first_key).to be false
        expect(@instance.get @first_key).to be_nil
        # Set cache again
        @instance.set(@first_key, nil, [$sample_file1])
        expect(@instance.hit? @first_key).to be true
      end
    end
    describe 'cache multiple files' do
      before(:all) do
        @instance = BuildCache::DiskCache.new($disk_cache_dir)
        @first_key = BuildCache.key_gen([$sample_file1, $sample_file2])
      end
      it 'should not be cached' do
        expect(@instance.hit? @first_key).to be false
        expect(@instance.get @first_key).to be_nil
      end
      it 'should cache files' do
        @instance.set(@first_key, nil, [$sample_file1, $sample_file2])
        expect(@instance.hit? @first_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file1))).to be true
        expect(File.exists?File.join(result_dir, File.basename($sample_file2))).to be true
      end
    end
    describe 'cache block' do
      before(:all) do
        @instance = BuildCache::DiskCache.new($disk_cache_dir)
        @instance.logger = @logger
        @input_files = [$sample_file1, $sample_file2]
        @metadata = {:cmd => 'my_cmd'}
        @dest_dir = rm_mkdir('buildcache_dest_dir')
        @first_key = BuildCache.key_gen @input_files, @metadata
        @second_key = @metadata.to_s
        @result1 = File.join(@dest_dir, 'result1.txt')
        @result2 = File.join(@dest_dir, 'result2.txt')
        @result_files = ['result1.txt', 'result2.txt']
      end
      it 'should cache files' do
        expect(@instance.hit? @first_key, @second_key).to be false
        files = @instance.cache(@input_files, @metadata, @dest_dir) do
          File.open(@result1, 'w') do |file|
            file.write("Sample result 1 \n")
          end
          File.open(@result2, 'w') do |file|
            file.write("Sample result 2 \n")
          end
          next @result_files
        end
        expect(@instance.hit? @first_key, @second_key).to be true
        expect(files).to eq @result_files
        expect(File.exist?File.join($disk_cache_dir, @first_key, 'last_used'))
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key, @second_key).to eq result_dir
        expect(File.exists?File.join(result_dir, 'result1.txt')).to be true
        expect(File.exists?File.join(result_dir, 'result2.txt')).to be true
      end
      it 'should retrieve cached files' do
        dest_dir2 = rm_mkdir('buildcache_dest_dir2')
        files = @instance.cache(@input_files, @metadata, dest_dir2) do
          should never get here
        end
        expect(files).to eq @result_files
        expect(File.exists?File.join(dest_dir2, 'result1.txt')).to be true
        expect(File.exists?File.join(dest_dir2, 'result2.txt')).to be true
      end
    end
    describe 'cache evict' do
      before(:all) do
        @instance = BuildCache::DiskCache.new($disk_cache_dir)
        @instance.logger = @logger
      end
      before(:each) do
        FileUtils.rm_rf(Dir[$disk_cache_dir + '/*'])
        expect(Dir[$disk_cache_dir + '/*'].empty?).to be true
      end
      it 'should evict entries' do
        @instance.check_size_percent = 0
        i = 0
        9.times do
          @instance.set("#{i}", nil, [$sample_file1])
          i += 1
        end
        @instance.set('2', '1', [$sample_file1])
        expect(Dir[$disk_cache_dir + '/*/*'].size).to be 10
        FileUtils.touch($disk_cache_dir + '/0/0/last_used', :mtime => Time.now + (2 * 60 * 60))
        FileUtils.touch($disk_cache_dir + '/1/0/last_used', :mtime => Time.now - (2 * 60 * 60))
        FileUtils.touch($disk_cache_dir + '/2/0/last_used', :mtime => Time.now - (2 * 60 * 60))
        FileUtils.touch($disk_cache_dir + '/2/1/last_used', :mtime => Time.now + (2 * 60 * 60))
        FileUtils.touch($disk_cache_dir + '/0/0/last_used')
        @instance.check_size_percent = 99.9
        @instance.max_cache_size = 9
        @instance.evict_percent = 50.0
        @instance.set('11', nil, [$sample_file1])
        expect(Dir[$disk_cache_dir + '/*/*'].size).to be 6
        expect(File.exist?File.join($disk_cache_dir, '0/0')).to be true
        expect(File.exist?File.join($disk_cache_dir, '1/0')).to be false
        expect(File.exist?File.join($disk_cache_dir, '2/0')).to be false
        expect(File.exist?File.join($disk_cache_dir, '2/1')).to be true
        # Cache a new entry in the directory that had 1 eviction
        @instance.set('2', 'new', [$sample_file1])
        expect(File.exist?File.join($disk_cache_dir, '2/0')).to be true
      end
    end
  end
  
end
