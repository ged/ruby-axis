#!/usr/bin/env rspec -cfd -b

BEGIN {
	require 'pathname'
	basedir = Pathname( __FILE__ ).dirname.parent.parent
	libdir = basedir + 'lib'

	$LOAD_PATH.unshift( basedir.to_s ) unless $LOAD_PATH.include?( basedir.to_s )
	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
}

require 'yaml'
require 'rspec'
require 'spec/lib/helpers'
require 'axis/camera'

describe Axis::Camera do

	before( :all ) do
		setup_logging( :fatal )
		@basedir = Pathname( __FILE__ ).dirname.parent.parent
		@testconfig = @basedir + 'test-camera.conf'
	end

	after( :all ) do
		reset_logging()
	end


	let( :config ) { YAML.load(@testconfig.read) }
	let( :camera ) { Axis::Camera.new(config.values_at( 'host', 'username', 'password' )) }


	it "bases its endpoint URL on the host it's created with" do
		Axis::Camera.new( 'outside-camera.example.com' ).endpoint.should ==
			URI( 'http://outside-camera.example.com/axis-cgi/' )
	end


	it "can fetch the firmware version of the camera" do
		camera.firmware_version.should =~ /\d+.\d+/
	end

end

