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
	include Axis::Loggable,
	        Axis::HashUtilities

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

	# Valid values for the 'level' argument to the #param methods.
	VALID_PARAM_LEVELS = [ :admin, :view, :operator ]


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

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


	### Fetch parameters from the camera at the given permission +level+, with
	### an optional +filter+, and return them as a simple Hash keyed by dotted property
	### name.
	### @param [Symbol] level  the permission level to restrict the results to (should be one of
	###                        {VALID_PARAM_LEVELS})
	### @param [String] filter Restrict the values returned to <group>.<name>. If <name> is 
	###                        omitted, all the parameters of the <group> are returned.
	###                        The camera parameters must be entered exactly as they are named 
	###                        in the camera or video server.
	###                        
	###                        Wildcards (*) can be used when listing parameters. See example below.
	###                        
	###                        If +filter+ is omitted, all parameters in the device are returned.
	### @example Fetch all parameters at the 'admin' level.
	###   cam.params( :admin )
	###   # => {"StatusLED.FlashInterval"=>4, 
	###   #     "Layout.CustomLink.C0.Name"=>"Custom link 1",
	###   #     "Event.E0.Type"=>"T", ...
	### @example Fetch all 'Network' parameters at the 'admin' level.
	###   cam.params( :admin, 'Network' )
	###   # => {"Network.RTSP.Port"=>554,
	###   #     "Network.RTP.R0.TTL"=>5, ...
	### @example Fetch the names of all events.
	###   cam.params( :admin, 'Event.*.Name' )
	###   # => {"Event.E0.Name"=>"Movement"}
	def params( level=:admin, filter=nil )
		self.log.debug "Fetching params hash for %s-level params, filter: %p" % [ level, filter ]
		args = { :action => 'list' }
		args.merge!( :group => filter ) if filter
		cachekey = "params_%s_%s" % [ level, filter ]

		return @cache.fetch( cachekey ) do
			self.log.debug "  cache miss for %p" % [ cachekey ]
			rawval = self.vapix_get( level, :param, args )
			rawval.each_line.inject( {} ) do |hash, line|
				key, val = line.chomp.split( /=\s*/, 2 )
				key.sub!( /^root\./, '' )

				hash[ key ] = parse_param_value( val )
				hash
			end
		end
	end


	### Fetch all parameters from the camera at the given permission +level+ as
	### a complex Hash.
	### @param [Symbol] level  the permission level to restrict the results to (should be one of
	###                        {VALID_PARAM_LEVELS})
	### @example Fetch the hash of all parameters at the 'view' level.
	###   cam.params_hash( :view )
	###   # => {"PTZ"=>{"Preset"=>{"P0"=>{"HomePosition"=>"-1", "Name"=>"", "ImageSource"=>0}}, 
	###   #             "Various"=>{"V1"=>{"MotionWhileZoomed"=>"false", "TiltEnabled"=>"true", ...
	def params_hash( level=:admin )
		self.log.debug "Fetching params hash for %s-level params" % [ level ]
		args = { :action => 'list' }
		cachekey = "params_#{level}"

		return @cache.fetch( cachekey ) do
			self.log.debug "  cache miss for %p" % [ cachekey ]
			rawval = self.vapix_get( level, :param, args )
			rawval.each_line.inject( {} ) do |hash, line|
				key, val = line.chomp.split( /=\s*/, 2 )
				keyparts = key.sub( /^root\./, '' ).split( '.' )

				# Find/create the inner-most hash by traversing all but the last parts of the key
				subhash = keyparts[ 0..-2 ].inject( hash ) do |subhash,keypart|
					subhash[ keypart ] ||= {}
				end

				# Add the parsed value to the innermost hash
				subhash[ keyparts.last ] = parse_param_value( val )

				hash
			end
		end
	end


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
		return self.params_hash( :view )['Brand']['Brand']
	end


	### Fetch the model of the camera as a string.
	### @return [String] the model of the camera
	def serial_number
		return self.params_hash( :view )['Properties']['System']['SerialNumber']
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


	### Fetch a bitmap image with the default resolution as defined in the system configuration
	### from the specified +camera+.
	### @param [Fixnum] camera  the camera number (for multi-camera devices)
	### @return [String] the raw bitmap image data
	### @note
	###    This doesn't work on my test camera, as it returns what appears to be two
	###    overlapping responses:
	###        GET /axis-cgi/bitmap/image.bmp?camera=1 HTTP/1.0
	###        Accept: */*
	###        Connection: keep-alive
	###        Authorization: Basic eWVwL25vcGU=
	###        Host: axis-camera-tester.example.com
	###        Keep-Alive: 30
    ###        
	###        HTTP/1.0 200 OK
	###        Date: Fri, 20 May 2011 10:33:08 GMT
	###        Accept-Ranges: bytes
	###        Connection: close
	###        Value:"/axis-cgi/bitmap/image.bmp"
	###        HTTP/1.0 200 OK
	###        Content-Type: image/bmp
	###        Content-Length: 921654
	###        
	###        <bitmap data>
	### 
	###   While I suppose I could just drop down to the raw socket level for this one 
	###   call and parse out the erroneous line from the response myself, given that 
	###   there are a bunch of other methods for fetching image data, I'm going to just
	###   leave this as-is.
	###
	### @raise [NotImplementedError] if the camera doesn't support bitmap images
	def get_bitmap( camera=1 )
		raise NotImplementedError, "This camera doesn't support the 'bitmap' image format" unless
			self.params['Properties.Image.Format'].include?( 'bitmap' )

		self.log.debug "Fetching bitmap image from camera %d" % [ camera ]
		bitmap = self.vapix_get( :bitmap, :image, '.bmp', :camera => camera )
		return bitmap
	end


	### Fetch a JPEG image from the specified +camera+.
	### @param [Hash] options    image options
	### @option options [String]  resolution  the resolution of the returned image; one of:
	###     1280x1024, 1280x960, 1280x720, 768x576, 4CIF,  704x576, 704x480, VGA, 640x480, 640x360, 
	###     2CIFEXP, 2CIF, 704x288, 704x240, 480x360,  CIF, 384x288, 352x288, 352x240, 320x240, 
	###     240x180, QCIF, 192x144, 176x144, 176x120, 160x120
	### @option options [Integer] camera      Selects the source camera; applies only to video 
	###     servers with more than one video input.
	### @option options [Integer] compression Adjusts the compression level of the image. Higher 
	###     values correspond to higher compression, i.e. lower quality and smaller image size.
	### @option options [Integer] colorlevel (0-100)  Sets level of color or grey-scale; 
	###     0 = grey-scale, 100 = full color. Note: This value is internally mapped and is 
	###     therefore product-dependent.
	### @option options [Boolean] color                Enable/disable color.
	### @option options [Boolean] clock                Shows/hides the time stamp.
	### @option options [Boolean] date                 Shows/hides the date.
	### @option options [Boolean] text                 Shows/hides the text.
	### @option options [String]  textstring           The text shown in the image.
	### @option options [String]  textcolor            ('black' or 'white') The color of the text shown 
	###     in the image.
	### @option options [String]  textbackgroundcolor  ('black', 'white', 'transparent', 
	###     'semitransparent') The color of the text background shown in the image.
	### @option options [Integer] rotation             (0, 90, 180, 270)  Rotates the image 
	###     clockwise.
	### @option options [String] textpos	           ('top', 'bottom') The position of the 
	###     string shown in the image.
	### @option options [Boolean] overlayimage         Enable/disable overlay image.
	### @option options [String] overlaypos            Set the position of the overlay image, in the
	###     form <xoffset>x<yoffset>, e.g., '18x20'.
	### @option options [Boolean] squarepixel          Enable/disable square pixel correction. 
	###     Applies only to video servers.
	### 
	### @return JPEG image data.
	### @raise [NotImplementedError] if the camera doesn't support JPEG images.
	def get_jpeg( options={} )
		raise NotImplementedError, "This camera doesn't support the 'jpeg' image format" unless
			self.params['Properties.Image.Format'].include?( 'jpeg' )

		# Translate boolean options to 1 or 0.
		options = symbolify_keys( options )
		[ :color, :clock, :date, :text, :overlayimage, :squarepixel ].each do |boolkey|
			options[ boolkey ] = options[ boolkey ] ? '1' : '0' if options.key?( boolkey )
		end

		self.log.debug "Fetching JPEG image with options: %p" % [ options ]
		jpeg = self.vapix_get( :jpg, :image, options )

		return jpeg
	end


	#########
	protected
	#########

	### Fetch the persistent HTTP connection, creating it if necessary.
	def http
		self.log.debug "Fetching HTTP connection."
		@http ||= Net::HTTP::Persistent.new( 'axis-camera' )
		@http.debug_output = $stderr if $DEBUG

		return @http
	end


	### Call the given +cgi+ in the specified +subdir+ and return the server response. Add any
	### +params+ to the request.
	def vapix_get( subdir, cgi, ext='.cgi', params={} )
		if ext.is_a?( Hash )
			params = ext
			ext = '.cgi'
		end

		url = URI( "%s/%s/%s%s" % [self.endpoint, subdir, cgi, ext] )
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
			[ dump_response_object(response), response.body[0,100].dump ]

		# Check for errors in the reponse body
		case body
		when /<!--(.*?error.*?)-->/i,
			 /^# error: (.*)$/i,
			 /^# request failed: (.*)$/i
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

	### Turn the given +value+ string from the 'param' CGI into a Ruby value and
	### return it. This maps 'yes' => true, 'no' => false, comma-delimited lists into 
	### Arrays, etc.
	def parse_param_value( value )
		return case value
		when 'yes'
			true
		when 'no'
			false
		when /^\d+$/
			Integer( value )
		when /^\d+\.\d+$/
			Float( value )
		when /,/
			value.split( /,\s*/ ).map( &method(:parse_param_value) )
		else
			value
		end
	end


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

