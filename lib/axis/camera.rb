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
	ENDPOINT_URI = URI( 'http://localhost/axis-cgi/' ).freeze

	# The pattern to use to split the server report up into sections
	SERVER_REPORT_DIVIDER = /^----- ([^\-]+) -----$/



	### Create a new Axis::Camera object that will interact with the
	### camera at +host+.
	### @param [IPAddr, String] host  the hostname or IP address of the camera
	def initialize( host, username, password )
		@endpoint = ENDPOINT_URI.dup
		@endpoint.host = host

		@username = username
		@password = password

		@http = nil
		@cache = Cache.new( 2**15, 2**16, 16, 60 )

		self.log.info "Created a camera proxy for #@endpoint"
	end


	######
	public
	######

	# @return [URI]  the URI of the camera API's endpoint
	attr_reader :endpoint


	### Fetch the camera's firmware version
	### @return [String] the version string
	def firmware_version
		release = self.server_report[ :etc_release ]
		return release[ /"([^"]+)"/, 1 ]
	end


	### Fetch the server report from the camera.
	### @return [Hash] the server report as a hash, keyed by section.
	def server_report
		report = @cache.fetch( :server_report ) do
			raw_report = self.call_admin_serverreport
			raw_report.split( SERVER_REPORT_DIVIDER ).inject
		end

	end


	#########
	protected
	#########



	def http
		@http ||= Net::HTTP::Persistent.new( 'axis-camera' )
	end


	def call_admin_serverreport
		url = "%s/%s/%s.cgi" % [ self.endpoint, 'admin', 'serverreport' ]
		req = Net::HTTP::Get.new( url.request_uri )
		req.basic_auth( @username, @password )

		response = self.http.request( url, req )

		return response.body		
	end

end # class Axis::Camera

