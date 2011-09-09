#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe Salmon::EncryptedSlap do
  let(:post){ alice.post :status_message, :text => "hi", :to => alice.aspects.create(:name => "sdg").id }

  let!(:created_salmon) {Salmon::EncryptedSlap.create(alice, post.to_diaspora_xml)}

  describe '#create' do

    it 'has data in the magic envelope' do
      created_salmon.magic_sig.data.should_not be nil
    end

    it 'has no parsed_data' do
      created_salmon.parsed_data.should be nil
    end

    it 'sets aes and iv key' do
      created_salmon.aes_key.should_not be nil
      created_salmon.iv.should_not be nil
    end

    it 'makes the data in the signature encrypted with that key' do
      key_hash = {'key' => created_salmon.aes_key, 'iv' => created_salmon.iv}
      decoded_string = Salmon::EncryptedSlap.decode64url(created_salmon.magic_sig.data)
      alice.aes_decrypt(decoded_string, key_hash).should == post.to_diaspora_xml
    end
  end

  describe '#xml_for' do
    let(:xml)   {created_salmon.xml_for eve.person}

    it 'has a encrypted header field' do
      xml.include?("encrypted_header").should be true
    end

    it 'the encrypted_header field should contain the aes key' do
      doc = Nokogiri::XML(xml)
      decrypted_header = eve.decrypt(doc.search('encrypted_header').text)
      decrypted_header.include?(created_salmon.aes_key).should be true
    end
  end

  context 'marshaling' do
    let(:xml)   {created_salmon.xml_for eve.person}
    let(:parsed_salmon) { Salmon::EncryptedSlap.parse(xml, eve)}

    it 'should parse out the aes key' do
      parsed_salmon.aes_key.should == created_salmon.aes_key
    end

    it 'should parse out the iv' do
      parsed_salmon.iv.should == created_salmon.iv
    end
    it 'should parse out the authors diaspora_handle' do
      parsed_salmon.author_email.should == alice.person.diaspora_handle

    end

    describe '#author' do
      it 'should reference a local author' do
        parsed_salmon.author.should == alice.person
      end

      it 'should fail if no author is found' do
        parsed_salmon.author_email = 'tom@tom.joindiaspora.com'


        proc {parsed_salmon.author.public_key}.should raise_error "did you remember to async webfinger?"

      end

    end

    it 'verifies the signature for the sender' do
      parsed_salmon.verified_for_key?(alice.public_key).should be true
    end

    it 'contains the original data' do
      parsed_salmon.parsed_data.should == post.to_diaspora_xml
    end

  end
end
