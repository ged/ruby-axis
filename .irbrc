#!/usr/bin/ruby -*- ruby -*-

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.expand_path
	libdir = basedir + "lib"

	puts ">>> Adding #{libdir} to load path..."
	$LOAD_PATH.unshift( libdir.to_s )
}

begin
	$stderr.puts "Loading Axis..."
	require 'axis'
rescue => e
	$stderr.puts "Ack! Axis library failed to load: #{e.message}\n\t" +
		e.backtrace.join( "\n\t" )
end

