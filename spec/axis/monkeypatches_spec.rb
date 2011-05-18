#!/usr/bin/env rspec -cfd -b
# encoding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname( __FILE__ ).dirname.parent.parent
	libdir = basedir + 'lib'

	$LOAD_PATH.unshift( basedir.to_s ) unless $LOAD_PATH.include?( basedir.to_s )
	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
}

require 'yaml'
require 'stringio'

require 'rspec'

require 'spec/lib/helpers'
require 'axis/camera'

describe "URI 1.9.x compatibility monkeypatches", :ruby_1_8_only => true do

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end


	it "adds an ::encode_www_form_component method to URI" do
		URI.encode_www_form_component( "http://monkeycall.net/" ).
			should == "http%3A%2F%2Fmonkeycall.net%2F"
	end

	it "adds a ::decode_www_form_component method to URI" do
		URI.decode_www_form_component( "http%3A%2F%2Fmonkeycall.net%2F" ).
			should == "http://monkeycall.net/"
	end

	it "adds an ::encode_www_form method to URI" do
		URI.encode_www_form([ ['a', '1'], ['a', '2'], ['b', '3'] ]).
			should == "a=1&a=2&b=3"
	end

	it "adds a ::decode_www_form method to URI" do
		URI.decode_www_form( "a=1&a=2&b=3" ).
			should == [ ['a', '1'], ['a', '2'], ['b', '3'] ]
	end

end

