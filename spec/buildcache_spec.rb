require 'spec_helper'

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
      end
      it 'should not be cached' do
        @first_key = BuildCache.key_gen([$sample_file1])
        expect(@instance.hit? @first_key).to be false
        expect(@instance.get @first_key).to be_nil
      end
      it 'should cache file' do
        @first_key = BuildCache.key_gen([$sample_file1])
        @instance.set(@first_key, nil, [$sample_file1])
        expect(@instance.hit? @first_key).to be true
        result_dir = File.join($disk_cache_dir, @first_key + '/0/content')
        expect(File.directory?result_dir).to be true
        expect(@instance.get @first_key).to eq result_dir
        expect(File.exists?File.join(result_dir, File.basename($sample_file1))).to be true
      end
    end
    describe 'cache multile files' do
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
  end
  
end
