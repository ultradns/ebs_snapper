# Copyright 2012 NeuStar, Inc. All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'ostruct'
require 'yaml'


class EbsSnapper::CLI
  
  def self.run  
    opts = parse(ARGV)
    ebs = EbsSnapper::Ebs.new(opts[:aws])
    ebs.snapshot_and_purge
  end
  
  def self.load_config(opts, filename)
    config = symbolize_keys(YAML.load_file(filename))
    # merge the new file config & update the logger config
    configure_logger(opts.merge!(config))
  end
  
  def self.configure_logger(opts)
    if opts[:log_to]
      @logger = ::Logger.new(opts[:log_to])
    end
    @logger ||= ::Logger.new(STDOUT)

    @logger.level = opts[:verbose] ? Logger::DEBUG : Logger::INFO
    
    opts[:aws][:logger] = @logger if opts[:aws]
    
    opts
  end
  
  def self.parse(args)
    options = {}
    options[:aws] = {}
    options[:ultradns] = {}
    options[:log_to] = nil
    options[:verbose] = false
    options[:out] = ''
    options[:config] = nil
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: ebs_snapper [options]"

      opts.separator ""
      opts.separator "Specific options:"

      opts.on("-c", "--config config.yaml",
              "Configuration for the updater") do |config|
        options[:config] = config
      end
            
      opts.separator ""

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options[:verbose] = v
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on_tail("--version", "Show version") do
        puts EbsSnapper::VERSION
        exit
      end
    end

    opts.parse!(args)
    # load the config
    load_config(options, options[:config])
  end
  
  def self.symbolize_keys(hash)
    unless hash.nil?
      hash.replace(
        hash.each_key.inject({}) do |h, k|
          v = hash.delete(k)
          key = k.to_sym rescue k
          if v.is_a? (Hash)
            h[key] = symbolize_keys(v)
          else
            h[key] = v
          end
          h
        end
      )
    end
    hash
  end
end

