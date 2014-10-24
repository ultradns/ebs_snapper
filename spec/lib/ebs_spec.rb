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

require 'spec_helper'
require 'fakeweb'
require 'ostruct'

describe EbsSnapper::Ebs do
  DEFAULT_TAG_NAME = EbsSnapper::Ebs::DEFAULT_TAG_NAME


  it "should run purge_old_snapshots in dry mode" do
    ebs = EbsSnapper::Ebs.new({}, true)
    ttl = EbsSnapper::Ebs::TTL.new("1.day") # 1 day
    region = OpenStruct.new

    snapshot_old = OpenStruct.new
    snapshot_old.status = :complete
    snapshot_old.tags = {DEFAULT_TAG_NAME => Time.now.utc.to_i - (86400 * 2)}
    expect(snapshot_old).to_not receive(:delete)

    region.snapshots = [snapshot_old]
    region.snapshots.stub(:filter).and_return(region.snapshots)

    ebs.purge_old_snapshots(ttl, region, 2)
  end

  it "should run snapshot_volume in dry mode" do
    ebs = EbsSnapper::Ebs.new({}, true)

    region = OpenStruct.new
    region.tags = []
    region.id = '999'

    volume = OpenStruct.new
    volume.should_not_receive(:create_snapshot)
    region.volumes = {3 => volume}

    expect(ebs.snapshot_volume(region, 3)).to eql(true)
  end

  it "should find tagged volumes in a region" do
    ebs = EbsSnapper::Ebs.new

    tag = OpenStruct.new
    tag.resource = OpenStruct.new(:id => 1)

    tags = [tag]
    tags.stub(:filter).and_return(tags)

    region = OpenStruct.new
    region.tags = tags
    region.id = '999'

    ebs.stub(:each_region).and_yield(region)

    vols = ebs.tagged_volumes
    expect(vols.size).to eql(1)

    expect(vols[0][:region].id).to eql(region.id)
    expect(vols[0][:volume_id]).to be == tag.resource.id
    expect(vols[0][:ttl]).to_not be == nil

    two_days_secs = EbsSnapper::Ebs::TTL.new().convert_to_seconds(0).to_i
    span_begin = (Time.now.utc.to_i - two_days_secs) - 10
    span_end = (Time.now.utc.to_i - two_days_secs) + 1
    expect(vols[0][:ttl].cut_off).to be > span_begin
    expect(vols[0][:ttl].cut_off).to be < span_end
  end

  it "should use retention from the tag in a volume in a region" do
    ebs = EbsSnapper::Ebs.new

    tag = OpenStruct.new
    tag.resource = OpenStruct.new(:id => 1)
    tag.value = "2.days"

    tags = [tag]
    tags.stub(:filter).and_return(tags)

    region = OpenStruct.new
    region.tags = tags
    region.id = '999'

    ebs.stub(:each_region).and_yield(region)

    vols = ebs.tagged_volumes
    vols.size.should == 1

    vols[0][:region].id.should == region.id
    vols[0][:volume_id].should == tag.resource.id
    vols[0][:ttl].should_not == nil

    two_days_secs = EbsSnapper::Ebs::TTL.new().convert_to_seconds('2.days').to_i
    span_begin = (Time.now.utc.to_i - two_days_secs) - 10
    span_end = (Time.now.utc.to_i - two_days_secs) + 1
    vols[0][:ttl].cut_off.should > span_begin
    vols[0][:ttl].cut_off.should < span_end
  end

  it "should pruge old timestamps" do
    ttl = EbsSnapper::Ebs::TTL.new("1.day") # 1 day
    ttl.purge?(Time.now.utc.to_i - (86400 * 3)).should == true
    ttl.purge?(Time.now.utc.to_i - (86400 + 3601)).should == true
    ttl.purge?("#{Time.now.utc.to_i - (86400 + 3601)}").should == true
  end

  it "shouldn't pruge new timestamps" do
    ttl = EbsSnapper::Ebs::TTL.new("1.day") # 1 day
    ttl.purge?(Time.now.utc.to_i - (3600)).should == false
    ttl.purge?(Time.now.utc.to_i - (86400 - 3600)).should == false
    ttl.purge?(Time.now.utc.to_i - (86400 + 3600)).should == false
    # we give it 1 hr around the timestamp
    ttl.purge?(Time.now.utc.to_i - 86400).should == false
  end

  it "should convert day ttls to seconds" do
    ttl = EbsSnapper::Ebs::TTL.new("1.day") # 1 day
    ttl.convert_to_seconds("1.day").should == 86400 + 3600
    cut_off_10 = ttl.convert_to_seconds("10.days")
    cut_off_10.should == (86400 * 10) + 3600
  end

  it "should convert hour ttls to seconds" do
    ttl = EbsSnapper::Ebs::TTL.new()
    ttl.convert_to_seconds("3.hours").should == (3600 * 3)
  end

  it "should set default ttl to seconds" do
    ten_days_secs = (86400 * 10) + 3600
    between_a = Time.now.utc.to_i - ten_days_secs
    ttl = EbsSnapper::Ebs::TTL.new()
    tm = Time.now.utc.to_i
    between_b = tm - ten_days_secs
    ttl.cut_off.should >= between_a
    ttl.cut_off.should <= between_b

    ttl.convert_to_seconds("asfljasdfjl").should == ten_days_secs
  end

  it "should snapshot a volume" do

    ebs = EbsSnapper::Ebs.new

    tag = OpenStruct.new
    tag.resource = OpenStruct.new(:id => 1)

    tags = [tag]
    tags.stub(:filter).and_return(tags)

    region = OpenStruct.new
    region.tags = tags
    region.id = '999'

    snapshot = Object.new
    expect(snapshot).to receive(:tag).with(DEFAULT_TAG_NAME,
      hash_including(:value => match(/^\d+/))) {true}

    volume = OpenStruct.new
    expect(volume).to receive(:create_snapshot) {snapshot}
    region.volumes = {3 => volume}
    ebs.snapshot_volume(region, 3).should == true

    # id 1 is not found (nil)
    ebs.snapshot_volume(region, 1).should == true
  end

  it "should purge old snapshots" do
    ebs = EbsSnapper::Ebs.new
    ttl = EbsSnapper::Ebs::TTL.new("1.day") # 1 day
    region = OpenStruct.new

    snapshot_old = OpenStruct.new
    snapshot_old.status = :complete
    snapshot_old.tags = {DEFAULT_TAG_NAME => Time.now.utc.to_i - (86400 * 2)}
    expect(snapshot_old).to receive(:delete)

    snapshot_old_error = OpenStruct.new
    snapshot_old_error.status = :error
    snapshot_old_error.tags = {DEFAULT_TAG_NAME => Time.now.utc.to_i - (86400 * 2)}
    expect(snapshot_old_error).to receive(:delete)


    snapshot_new = OpenStruct.new
    snapshot_new.status = :complete
    snapshot_new.tags = {DEFAULT_TAG_NAME => Time.now.utc.to_i - (3600 * 3)}
    expect(snapshot_new).to_not receive(:delete)

    snapshot_pending = OpenStruct.new
    snapshot_pending.status = :pending
    snapshot_pending.tags = {DEFAULT_TAG_NAME => Time.now.utc.to_i - (86400 * 3)}
    expect(snapshot_pending).to_not receive(:delete)

    region.snapshots = [snapshot_old, snapshot_new, snapshot_pending, snapshot_old_error]
    region.snapshots.stub(:filter).and_return(region.snapshots)

    ebs.purge_old_snapshots(ttl, region, 2)
  end

  it "should flow through snapshot and purge" do
    ebs = EbsSnapper::Ebs.new
    ebs.stub(:tagged_volumes).and_return([{
      :ttl => EbsSnapper::Ebs::TTL.new("1.day"),
      :region => 'us-east-1',
      :volume_id => 1
    }])

    expect(ebs).to receive(:snapshot_volume).with(anything(), anything()).once
    expect(ebs).to receive(:purge_old_snapshots).with(anything(), anything(), anything()).once

    ebs.snapshot_and_purge()
  end
end
