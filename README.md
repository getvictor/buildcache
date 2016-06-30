[![Build Status](https://travis-ci.org/getvictor/buildcache.svg?branch=master)](https://travis-ci.org/getvictor/buildcache)

# BuildCache

A simple cache for files. It is currently used in production to cache the results of frequently run built steps (using a custom build flow).

The cache receives the input files and some metadata. It generates a hash key and checks the cache. If the cache is hit, the files are copied from the cache to the provided location. If we have a cache miss, the provided block is run, and the resulting files are copied to the cache.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'buildcache'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install buildcache

## Usage

### Block Style

    :::ruby
    require 'buildcache'
    @my_cache = BuildCache::DiskCache.new('/tmp/cache')
    @input_files = ['./input.txt']
    @metadata = {:cmd => 'parse input'}
    @dest_dir = './build'
    @my_cache.cache(@input_files, @metadata, @dest_dir) do
      # This is time consuming code where you generate result files.
      # The block is only run on a cache miss
      ...
      # You must return resulting files so they can be cached
      next files
    end

### Use API

The cache uses 2 keys. The `first_key` corresponds to directory name in the cache. `second_key` (optional) is held in a file and is used to resolve hash conflicts on first_key.

The following methods are available:

    :::ruby
    # Generate first_key
    first_key = BuildCache.key_gen(input_files_array, metadata)
    
    :::ruby
    # Check for a cache hit
    @my_cache.hit?(first_key, second_key)
    
    :::ruby
    # Set the cache
    @my_cache.set(first_key, second_key, files_array)
    
    :::ruby
    # Retrieve from cache. The result is a cache directory where the files are stored
    contents_dir = @my_cache.get(first_key, second_key)
    
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/getvictor/buildcache.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

