require "spec_helper"

describe Tamashii::Client do
  it "has a version number" do
    expect(Tamashii::Client::VERSION).not_to be nil
  end

  it "can get config" do
    expect(Tamashii::Client.config).to be(Tamashii::Client::Config)
  end

  it "can get logger" do
    expect(Tamashii::Client.logger).to be_instance_of(Tamashii::Logger)
  end

end
