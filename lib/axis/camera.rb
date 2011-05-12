#!/usr/bin/env ruby

require 'cache'

require 'uri'
require 'net/http'
require 'net/http/persistent'

require 'axis' unless defined?( Axis )


# The main network camera class. This is basically a frontend to the
# VAPIX® HTTP API of the camera, and so requires that the camera be
# running at least version 4 of the firmware.
class Axis::Camera
	include Axis::Loggable

	# The default camera endpoint -- this is combined with the camera
	# host for each instance to build all the rest of the actions
	ENDPOINT_URI = URI( 'http://localhost/axis-cgi' ).freeze

	# The pattern to use to split the server report up into sections
	SERVER_REPORT_DIVIDER = /(?:^|\r?\n)----- (.*?) -----\r?\n/

	# End-of-line characters
	EOL = /\r?\n/

	# The maximum size (in bytes) to cache for a single object
	MAX_CACHE_OBJECT_SIZE = 2 ** 17 # 128K

	# The maximum size (in bytes) to cache for all objects
	MAX_TOTAL_CACHE_SIZE = 2 ** 21  # 2M

	# The maximum number of objects to cache
	MAX_CACHED_OBJECT_COUNT = 16

	# The maximum number of seconds a cached object lives in the cache
	MAX_CACHE_LIFETIME = 60


	### Create a new Axis::Camera object that will interact with the
	### camera at +host+.
	### @param [IPAddr, String] host  the hostname or IP address of the camera
	def initialize( host, username=nil, password=nil )
		@endpoint = ENDPOINT_URI.dup
		@endpoint.host = host

		@username = username
		@password = password

		@http = nil
		@cache = Cache.new( MAX_CACHE_OBJECT_SIZE, 
		                    MAX_TOTAL_CACHE_SIZE, 
		                    MAX_CACHED_OBJECT_COUNT,
		                    MAX_CACHE_LIFETIME )

		self.log.info "Created a camera proxy for #@endpoint"
	end


	######
	public
	######

	# @return [URI]  the URI of the camera API's endpoint
	attr_reader :endpoint

	# @return [String]  the username to use when connecting
	attr_accessor :username

	# @return [String]  the password to use when connecting
	attr_accessor :password


	### Fetch the server report from the camera.
	### @return [Hash] the server report as a hash, keyed by section.
	def server_report
		return @cache.fetch( :server_report ) do
			self.log.debug "Cache miss for server_report."
			raw_report = self.get_admin_serverreport
			self.log.debug "  got %d bytes of report data." % [ raw_report.size ]

			# Split the report into a hash keyed by normalized symbols
			pairs = raw_report.
				split( Axis::Camera::SERVER_REPORT_DIVIDER ).
				slice( 1..-1 )
			self.log.debug "  split raw report into %d sections" % [ pairs.length / 2 ]

			pairs.each_slice( 2 ).
				inject( {} ) do |hash, (key, val)|
					self.log.debug "    adding the %s section: \"%s...\"." % [ key, val[0,40] ]
					keysym = key.downcase.
						gsub( /\W+/, '_' ).
						gsub( /(^_+|_+$)/, '' ).
						untaint.to_sym
					self.log.debug "    key is: %p" % [ keysym ]
					hash[ keysym ] = val
					hash
				end
		end
	end


	### Fetch the camera firmware's full release ID
	### @return [String] the firmware release ID in the form "id-<part>-<release>-<build>"
	### @example
	###   cam.firmware_release
	###   # => "id-36065-4.49-8"
	def firmware_release
		release = self.server_report[ :etc_release ]
		return release[ /"([^"]+)"/, 1 ]
	end


	### Fetch the model of the camera as a string.
	### @return [String] the model of the camera
	def model
		data = self.server_report[ :server_report_start ]
		return data[ /Product: (.*?)\r?\n/, 1 ]
	end


	### Fetch the model of the camera as a string.
	### @return [String] the model of the camera
	def serial_number
		data = self.server_report[ :server_report_start ]
		return data[ /Serial No: (.*?)\r?\n/, 1 ]
	end


	### Fetch the release variables that describe the camera's firmware as a Hash.
	### @return [Hash<Symbol, String>]  the hash of release variables
	def axis_release_variables
		raw_section = self.server_report[ :usr_share_axis_release_variables ]
		self.log.debug "Fetching release variables from %d bytes of raw data." % [ raw_section.length ]

		return raw_section.strip.split( EOL ).inject( {} ) do |hash, line|
			self.log.debug "  splitting up variable line: %p" % [ line ]
			key, val = line.strip.split( '=', 2 )
			self.log.debug 
			hash[ key.downcase.untaint.to_sym ] = dequote( val )
			hash
		end
	end


	### Fetch the camera firmware's decimal release version.
	### @return [String] firmware version number
	### @example
	###   cam.firmware_version
	###   # => "4.49"
	def firmware_version
		release_vars = self.axis_release_variables
		return release_vars[ :release ]
	end


	### Fetch the camera's "system information" (uname -a)
	def system_information
		return self.server_report[ :system_information ]
	end


	### Fetch a list of the user accounts on the camera.
	def users
		raw_output = self.vapix_get( :admin, :pwdgrp, :action => 'get' )
		return raw_output.split( EOL ).inject( {} ) do |hash, line|
			user, groups = line.split( '=', 2 )
			hash[ user ] = dequote( groups ).split( ',' )
			hash
		end
	end

	# :TODO: 
	# add_user( username, params={} )
	# remove_user( username )
	# update_user( username, params={} )


	### Fetch the default image size. If the optional +camera+ parameters is specified, the size
	### of additional onboard cameras will be queried.
	### @return [Array<Fixnum, Fixnum>]  the size in pixels: height, width
	### @example
	###   cam.image_size
	###   # => [ 176, 144 ]
	def image_size( camera=1 )
		self.log.debug "Fetching image size for camera %d" % [ camera ]
		raw_output = self.vapix_get( :view, :imagesize, :camera => camera )
		self.log.debug "  raw size output:\n%s" % [ raw_output ]

		width = raw_output[ /image width = (\d+)/i, 1 ]
		height = raw_output[ /image height = (\d+)/i, 1 ]

		return [ Integer(height), Integer(width) ]
	end


	### Check the video status of the specified +camera+. 
	### @return [boolean] +true+ if video is enabled.
	### @note This doesn't work on my test camera; it returns a 404.
	def video_status( camera=1 )
		self.log.debug "Fetching video status for camera %d" % [ camera ]
		raw_output = self.vapix_get( :view, :videostatus, :status => camera )
		self.log.debug "  raw video status output:\n%s" % [ raw_output ]

		return (raw_output !~ /video #{camera} = no video/i)
	end


	#########
	protected
	#########

	### Fetch the persistent HTTP connection, creating it if necessary.
	def http
		self.log.debug "Fetching HTTP connection."
		@http ||= Net::HTTP::Persistent.new( 'axis-camera' )
	end


	### Call the given +cgi+ in the specified +subdir+ and return the server response. Add any
	### +params+ to the request.
	def vapix_get( subdir, cgi, params={} )
		url = URI( "%s/%s/%s.cgi" % [self.endpoint, subdir, cgi] )
		self.log.debug "Vapix API call to %s as a %s user..." % [ cgi, subdir ]

		url.query = self.make_query_args( params ) unless params.empty?

		# Build the request object
		self.log.debug "  authing as %s with password %s" % [ @username, '*' * @password.length ]
		req = Net::HTTP::Get.new( url.request_uri )
		req.basic_auth( @username, @password )

		# Send the request
		self.log.debug "  fetching %s using: %p" % [ url, req ]
		response = self.http.request( url, req )
		response.value

		body = response.body
		self.log.debug "  response: %s%s" % 
			[ dump_response_object(response), response.body ]

		# Check for errors in the reponse body
		case body
		when /<!--(.*?error.*?)-->/i, /^# error: (.*)$/i, /^# request failed: (.*)$/i
			raise Axis::ParameterError, $1
		end

		return body
	rescue Net::HTTPServerException => err
		self.log.error "%s when fetching %s/%s: %s" %
			[ err.class.name, subdir, cgi, err.message ]

		case err.response.code.to_i
		when 404
			msg = "Your camera apparently doesn't implement the %s.cgi. " % [ cgi ]
			msg << "It sent a 404 response and said: %s" % [ err.message ]

			raise NotImplementedError, msg
		else
			raise ScriptError, "unhandled %p:\n%s" %
				[ err.response, dump_response_object(err.response) ]
		end
	end


	### Turn the parameters from the given +paramhash+ with either single values or arrays of 
	### values into an array of parameter tuples, then encode it as urlencoded form values.
	### @param [Hash] paramhash  the parameter hash. Array values will be expanded into multiple
	###                          query arguments.
	### @return [String] the query string
	def make_query_args( paramhash )
		self.log.debug "Making query args from paramhash: %p" % [ paramhash ]

		paramlist = paramhash.inject([]) do |array, (key, values)|
			Array( values ).each {|val| array << [key.to_s, val.to_s] }
			array
		end
		self.log.debug "  flattened request params into: %p" % [ paramlist ]

		return URI.encode_www_form( paramlist )
	end


	### Fetch the server report.
	def get_admin_serverreport
		return self.vapix_get( :admin, :serverreport )
	end


	#######
	private
	#######

	### Return the request object as a string suitable for debugging
	def dump_request_object( request )
		buf = "#{request.method} #{request.path} HTTP/#{Net::HTTP::HTTPVersion}\r\n"
		request.each_capitalized do |k,v|
			buf << "#{k}: #{v}\r\n"
		end
		buf << "\r\n"

		return buf
	end


	### Return the response object as a string suitable for debugging
	def dump_response_object( response )
		buf = "#{response.code} #{response.message}\r\n"
		response.each_capitalized do |k,v|
			buf << "#{k}: #{v}\r\n"
		end
		buf << "\r\n"

		return buf
	end


	### Strip one pair of leading and trailing quotes from +string+ and return the result.
	def dequote( string )
		return string.gsub( /(^"|"$)/, '' )
	end

end # class Axis::Camera

