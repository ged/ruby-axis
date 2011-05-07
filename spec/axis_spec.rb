#!/usr/bin/env rspec -cfd -b

BEGIN {
	require 'pathname'
	basedir = Pathname( __FILE__ ).dirname.parent
	libdir = basedir + 'lib'

	$LOAD_PATH.unshift( basedir.to_s ) unless $LOAD_PATH.include?( basedir.to_s )
	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
}

require 'rspec'
require 'spec/lib/helpers'
require 'axis'

describe Axis do

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end


	SEMANTIC_VERSION = /\d+(\.\d+){2,}/


	it "has a semantic-versioning constant" do
		Axis::VERSION.should =~ SEMANTIC_VERSION
	end


	it "has a string version" do
		Axis.version_string.should =~ /^\w+ #{SEMANTIC_VERSION}$/
	end


	it "can include a build ID in the version string" do
		Axis.version_string( true ).should =~ /^\w+ #{SEMANTIC_VERSION} \(build [[:xdigit:]]+\)$/
	end


	it "has a default Logger object" do
		Axis.logger.should be_a( Logger )
	end

	it "should know if its default logger is replaced" do
		Axis.reset_logger
		Axis.should be_using_default_logger
		Axis.logger = Logger.new( $stderr )
		Axis.should_not be_using_default_logger
	end

end

