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

require 'aws-sdk'

class EbsSnapper::Ebs
  
  DEFAULT_TAG_NAME = 'Snapper'
  DEFAULT_PAUSE_TIME = 0
  
  def initialize(opts = {}, dry_run = false)
    @dry_run = dry_run
    @logger = opts[:logger] || Logger.new(STDOUT)
    max_retries = opts[:max_retries] || AWS.config.max_retries
    if !opts[:secret_access_key].nil? && !opts[:access_key_id].nil?
      AWS.config(:access_key_id => opts[:access_key_id],
                 :secret_access_key => opts[:secret_access_key],
                 :logger => @logger,
                 :max_retries => max_retries) 
    else
      AWS.config(:logger => @logger,
                 :max_retries => max_retries) 
    end

    @retain = opts[:retain]
    @tag_name = opts[:volume_tag] || DEFAULT_TAG_NAME # default
    PausingEnumerable.pause_time = opts[:pause_time] || DEFAULT_PAUSE_TIME
    @logger.info "Initializing"
    @logger.info {"Dry run mode: #{@dry_run}"}
    @logger.info {"AWS SDK max retries: #{AWS.config.max_retries}"}
  end
  
  def snapshot_and_purge
    # now snapshot the list
    tagged_volumes.each do |vol_info|
      snapshot_volume(vol_info[:region], vol_info[:volume_id])
      purge_old_snapshots(vol_info[:ttl], vol_info[:region], vol_info[:volume_id])
    end
  end
  
  def tagged_volumes
    volumes = []
    
    each_region do |r|
      tags = r.tags.filter('resource-type', 'volume').filter('key', @tag_name)
      PausingEnumerable.wrap(tags).each do |tag|
        # if the tag exists, it's using the default retention (TTL)
        ttl_value = @retain
        if tag.value != nil && !tag.value.strip.empty?
          ttl_value = tag.value.strip
        end
        
        volumes << {
          :ttl => TTL.new(ttl_value),
          :region => r,
          :volume_id => tag.resource.id # volume id
        }
      end
    end
    volumes
  end
  
  def snapshot_volume(region, vol_id)
    vol = region.volumes[vol_id]
    if vol != nil
      if dry_run?
        @logger.info {"Dry run - would have called vol.create_snapshot for volume #{vol_id}"}
        @logger.info {"Dry run - would have called snapshot.tag for new snapshot of volume #{vol_id}"}
      else 
        timestamp = Time.now.utc
        @logger.info {"Snapshotting #{vol_id} at: #{timestamp}"}
        snapshot = vol.create_snapshot("Snapper Backup #{timestamp}")
        # tag the snapshot with the timestamp so we can look it up later for cleanup
        snapshot.tag(@tag_name, :value => "#{timestamp.to_i}")
      end
    else
      @logger.error "Error: Volume #{vol_id} in Region: #{region} not found"
    end
  end
  
  def purge_old_snapshots(ttl, region, vol_id)
    snapshots = region.snapshots.filter('volume-id', vol_id).filter('tag-key', @tag_name)
    PausingEnumerable.wrap(snapshots).each do |snapshot|
      unless snapshot.status == :pending
        ts = snapshot.tags[@tag_name]
        if ttl.purge?(ts)
          begin
            if dry_run?
              @logger.info {"Dry run - would have called snapshot.delete for snapshot #{snapshot.id} of volume #{vol_id}"}
            else
              @logger.info {"Purging #{vol_id} snapshot: #{snapshot.id}"}
              snapshot.delete
            end
          rescue => e
            @logger.error "Exception: #{e}\n" + e.backtrace().join("\n")
          end
        end
      end
    end
  end
  
  def dry_run?
    @dry_run == true
  end

  module PausingEnumerable
    
    def self.pause_time=(time)
       @pause_time = time
    end
    
    def self.pause_time
       @pause_time || EbsSnapper::Ebs::DEFAULT_PAUSE_TIME
    end
    
    def self.included(base)
      base.class_eval do
        if !method_defined?(:orig_each)
          alias_method :orig_each, :each
          def each(&block)
            orig_each(&block)
            sleep PausingEnumerable.pause_time # we need to slow down our processing..
          end
        end
      end
    end
    
    def self.wrap(enumerable)
      enumerable.class.module_eval do
        include PausingEnumerable
      end
      enumerable
    end
  end
  

  def each_region
    ec2.regions.each do |region|
      yield (region)
    end
  end
  
  def ec2
    @ec2 ||= AWS::EC2.new
    @ec2
  end
  
  class TTL
    DEFAULT_TTL = (86400 * 10) + 3600  # 10 days in hours
    attr_reader :cut_off
    
    def initialize(ttl = "10.days")
      @cut_off = Time.now.utc.to_i - convert_to_seconds(ttl)
    end
    
    def purge?(timestamp)
      ts = timestamp.to_i
      ts > 0 && (ts < @cut_off)
    end
    
    def convert_to_seconds(ttl)
      ttl_secs = ttl.to_i
      if ttl.kind_of?(String)
        if ttl =~ /\.day/
          # add 1 hr for backup time to extend the save-period.. TODO: maybe more..
          ttl_secs = (ttl.to_i * 86400) + 3600
        elsif ttl =~ /\.hour/
          ttl_secs = ttl.to_i * 3600
        end
      end
      ttl_secs == 0 ? DEFAULT_TTL : ttl_secs
    end
  end
end
