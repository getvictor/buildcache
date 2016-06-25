require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'buildcache'

def rm_mkdir dir
  new_dir = File.join(Dir.tmpdir, dir)
  if File.directory?(new_dir)
    FileUtils.rm_rf(new_dir)
  end
  Dir.mkdir(new_dir)
  return new_dir
end

# Create an existing cache directory
$disk_cache_dir = rm_mkdir('buildcache')

# Create some sample files
data_dir = rm_mkdir('buildcache_data')
$sample_file1 = File.join(data_dir, 'sample1.txt')
File.open($sample_file1, 'w') do |file|
  file.write("Sample file \n")
end
$sample_file2 = File.join(data_dir, 'sample2.txt')
File.open($sample_file2, 'w') do |file|
  file.write("Sample file 2 \n")
end
