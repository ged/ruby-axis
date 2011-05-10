#!/usr/bin/env ruby

require 'axis' unless defined?( Axis )
require 'spec/lib/helpers' unless defined?( Axis::SpecHelpers )


### A collection of constants used in testing
module Axis::TestConstants # :nodoc:all

	BASEDIR          = Pathname( __FILE__ ).dirname.parent.parent
	TEST_CONFIG_FILE = BASEDIR + 'test-camera.conf'

end


