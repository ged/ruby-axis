#!/usr/bin/ruby
# coding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
}

require 'rspec'
require 'spec/lib/constants'
require 'axis'


### RSpec helper functions.
module Axis::SpecHelpers
	include Axis::TestConstants

	class ArrayLogger
		### Create a new ArrayLogger that will append content to +array+.
		def initialize( array )
			@array = array
		end

		### Write the specified +message+ to the array.
		def write( message )
			@array << message
		end

		### No-op -- this is here just so Logger doesn't complain
		def close; end

	end # class ArrayLogger


	unless defined?( LEVEL )
		LEVEL = {
			:debug => Logger::DEBUG,
			:info  => Logger::INFO,
			:warn  => Logger::WARN,
			:error => Logger::ERROR,
			:fatal => Logger::FATAL,
		  }
	end

	###############
	module_function
	###############

	### Make an easily-comparable version vector out of +ver+ and return it.
	def vvec( ver )
		return ver.split('.').collect {|char| char.to_i }.pack('N*')
	end


	### Reset the logging subsystem to its default state.
	def reset_logging
		Axis.reset_logger
	end


	### Alter the output of the default log formatter to be pretty in SpecMate output
	def setup_logging( level=Logger::FATAL )

		# Turn symbol-style level config into Logger's expected Fixnum level
		if Axis::LOG_LEVELS.key?( level.to_s )
			level = Axis::LOG_LEVELS[ level.to_s ]
		end

		logger = Logger.new( $stderr )
		Axis.logger = logger
		Axis.logger.level = level

		# Only do this when executing from a spec in TextMate
		if ENV['HTML_LOGGING'] || (ENV['TM_FILENAME'] && ENV['TM_FILENAME'] =~ /_spec\.rb/)
			Thread.current['logger-output'] = []
			logdevice = ArrayLogger.new( Thread.current['logger-output'] )
			Axis.logger = Logger.new( logdevice )
			# Axis.logger.level = level
			Axis.logger.formatter = Axis::HtmlLogFormatter.new( logger )
		end
	end


	### Load the testing camera config options from a YAML file.
	def load_camera_config
		unless defined?( @camera_config ) && @camera_config
			if TEST_CONFIG_FILE.exist?
				$stderr.puts "Loading camera config from #{TEST_CONFIG_FILE}" if $VERBOSE
				@camera_config = YAML.load( TEST_CONFIG_FILE.read )
			else
				$stderr.puts "Skipping tests that require camera access. Copy the ",
					"#{TEST_CONFIG_FILE}.example file and provide valid values for testing",
					"with an actual camera."
				@camera_config = {}
			end
		end

		return @camera_config
	end

end


### Mock with Rspec
Rspec.configure do |c|
	include Axis::TestConstants

	c.mock_with :rspec
	c.include( Axis::SpecHelpers )

	c.filter_run_excluding( :ruby_1_9_only => true ) if
		Axis::SpecHelpers.vvec( RUBY_VERSION ) < Axis::SpecHelpers.vvec('1.9.0')
	c.filter_run_excluding( :ruby_1_8_only => true ) if
		Axis::SpecHelpers.vvec( RUBY_VERSION ) >= Axis::SpecHelpers.vvec('1.9.0')
	c.filter_run_excluding( :config_exists => true ) unless
		TEST_CONFIG_FILE.exist?
end

# vim: set nosta noet ts=4 sw=4:

