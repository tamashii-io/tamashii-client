require 'spec_helper'

RSpec.describe Tamashii::Client::Config do

  subject { Tamashii::Client::Config.new }

  describe "#log_file" do
    it "default output to STDOUT" do
      expect(subject.log_file).to eq(STDOUT)
    end
  end

  describe "#log_level" do
    it "default to DEBUG" do
      expect(subject.log_level).to eq(Logger::DEBUG)
    end

    it "can be changed" do
      subject.log_level(Logger::INFO)
      expect(subject.log_level).to eq(Logger::INFO)
    end
  end
end
