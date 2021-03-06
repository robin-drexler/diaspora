#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe Photo do
  before do
    @user = alice
    @aspect = @user.aspects.first

    @fixture_filename  = 'button.png'
    @fixture_name      = File.join(File.dirname(__FILE__), '..', 'fixtures', @fixture_filename)
    @fail_fixture_name = File.join(File.dirname(__FILE__), '..', 'fixtures', 'msg.xml')

    @photo  = @user.build_post(:photo, :user_file=> File.open(@fixture_name), :to => @aspect.id)
    @photo2 = @user.build_post(:photo, :user_file=> File.open(@fixture_name), :to => @aspect.id)
  end


  describe "#process" do
    it "should do something awesome"
  end

  describe "protected attributes" do
    it "doesn't allow mass assignment of person" do
      @photo.save!
      @photo.update_attributes(:author => Factory(:person))
      @photo.reload.author.should == @user.person
    end
    it "doesn't allow mass assignment of person_id" do
      @photo.save!
      @photo.update_attributes(:author_id => Factory(:person).id)
      @photo.reload.author.should == @user.person
    end
    it 'allows assignment of text' do
      @photo.save!
      @photo.update_attributes(:text => "this is awesome!!")
      @photo.reload.text.should == "this is awesome!!"
    end
  end

  describe 'after_create' do
    it 'calls #queue_processing_job' do
      @photo.should_receive(:queue_processing_job)

      @photo.save!
    end
  end

  it 'is mutable' do
    @photo.mutable?.should == true
  end

  it 'has a random string key' do
    @photo2.random_string.should_not be nil
  end

  describe '#diaspora_initialize' do
    before do
      image = File.open(@fixture_name)
      @photo = Photo.diaspora_initialize(
                :author => @user.person, :user_file => image)
    end
    it 'sets the persons diaspora handle' do
      @photo2.diaspora_handle.should == @user.person.diaspora_handle
    end
    it 'builds the photo without saving' do
      @photo.created_at.nil?.should be_true
      @photo.unprocessed_image.read.nil?.should be_false
    end
  end

  describe '#update_remote_path' do
    before do
      image = File.open(@fixture_name)
      @photo = Photo.diaspora_initialize(
                :author => @user.person, :user_file => image)
      @photo.processed_image.store!(@photo.unprocessed_image)
      @photo.save!
    end
    it 'sets a remote url' do
      @photo.update_remote_path

      @photo.remote_photo_path.should include("http")
      @photo.remote_photo_name.should include(".png")
    end
  end

  it 'should save a photo' do
    @photo.unprocessed_image.store! File.open(@fixture_name)
    @photo.save.should == true
    begin
      binary = @photo.unprocessed_image.read.force_encoding('BINARY')
      fixture_binary = File.open(@fixture_name).read.force_encoding('BINARY')
    rescue NoMethodError # Ruby 1.8 doesn't have force_encoding
      binary = @photo.unprocessed_image.read
      fixture_binary = File.open(@fixture_name).read
    end
    binary.should == fixture_binary
  end

  context 'with a saved photo' do
    before do
      @photo.unprocessed_image.store! File.open(@fixture_name)
    end
    it 'should have text' do
      @photo.text= "cool story, bro"
      @photo.save.should be_true
    end

    it 'should remove its reference in user profile if it is referred' do
      @photo.save

      @user.profile.image_url = @photo.url(:thumb_large)
      @user.person.save
      @photo.destroy
      Person.find(@user.person.id).profile[:image_url].should be_nil
    end

    it 'should not use the imported filename as the url' do
      @photo.url.include?(@fixture_filename).should be false
      @photo.url(:thumb_medium).include?("/" + @fixture_filename).should be false
    end
  end

  describe 'non-image files' do
    it 'should not store' do
      file = File.open(@fail_fixture_name)
      lambda {
        @photo.unprocessed_image.store! file
      }.should raise_error CarrierWave::IntegrityError, 'You are not allowed to upload "xml" files, allowed types: ["jpg", "jpeg", "png", "gif"]'
    end

  end

  describe 'serialization' do
    before do
      @photo.process
      @photo.save!
      @xml = @photo.to_xml.to_s
    end
    it 'serializes the url' do
      @xml.include?(@photo.remote_photo_path).should be true
      @xml.include?(@photo.remote_photo_name).should be true
    end
    it 'serializes the diaspora_handle' do
      @xml.include?(@user.diaspora_handle).should be true
    end
  end

  describe 'remote photos' do
    it 'should set the remote_photo on marshalling' do
      @photo.process
      @photo.save!
      #security hax
      user2 = Factory.create(:user)
      aspect2 = user2.aspects.create(:name => "foobars")
      connect_users(@user, @aspect, user2, aspect2)

      url = @photo.url
      thumb_url = @photo.url :thumb_medium

      xml = @photo.to_diaspora_xml

      @photo.destroy
      zord = Postzord::Receiver::Private.new(user2, :person => @photo.author)
      zord.parse_and_receive(xml)

      new_photo = Photo.where(:guid => @photo.guid).first
      new_photo.url.nil?.should be false
      new_photo.url.include?(url).should be true
      new_photo.url(:thumb_medium).include?(thumb_url).should be true
    end
  end

  context "commenting" do
    it "accepts comments if there is no parent status message" do
      proc{ @user.comment("big willy style", :post => @photo) }.should change(@photo.comments, :count).by(1)
    end
  end

  describe '#queue_processing_job' do
    it 'should queue a resque job to process the images' do
      Resque.should_receive(:enqueue).with(Job::ProcessPhoto, @photo.id)
      @photo.queue_processing_job
    end
  end

  context "deletion" do
    before do
      @status_message = @user.build_post(:status_message, :text => "", :to => @aspect.id)
      @status_message.photos << @photo2
      @status_message.save
      @status_message.reload
    end

    it 'is deleted with parent status message' do
      expect {
        @status_message.destroy
      }.should change(Photo, :count).by(-1)
    end
  end
end
