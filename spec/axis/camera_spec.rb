#!/usr/bin/env rspec -cfd -b

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

describe Axis::Camera do

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end


	it "bases its endpoint URL on the host it's created with" do
		Axis::Camera.new( 'outside-camera.example.com' ).endpoint.should ==
			URI( 'http://outside-camera.example.com/axis-cgi' )
	end


	context "with a stubbed camera" do

		before( :each ) do
			@camera = Axis::Camera.new( 'dummyhost', 'user', 'pass' )
			@http = stub( "http client" )
			@camera.instance_variable_set( :@http, @http )
		end

		COMMENT_ERROR_RESPONSE = %{
			<!-- Error getting image params. Check syslog. -->
		}.gsub( /\t{3}/m, "" ).lstrip

		it "handles comment-style error returns by raising an Axis::ParameterError" do
			response = mock( "http response",
				:code => '200', :message => "OK", :each_capitalized => {}, :value => nil )
			@http.stub( :request ).and_return( response )
			response.stub( :body ).and_return( COMMENT_ERROR_RESPONSE )

			expect {
				@camera.image_size( 2 )
			}.to raise_exception( Axis::ParameterError, /error getting image params/i )
		end

		NOT_FOUND_RESPONSE = %{
			<HTML><HEAD><TITLE>404 Not Found</TITLE></HEAD>
			<BODY><H1>404 Not Found</H1>
			The requested URL /axis-cgi/view/videostatus.cgi was not found on this server.
			</BODY></HTML>
		}.gsub( /^\t{3}/m, "" ).strip

		it "handles a 404 by raising a NotImplementedError" do
			response = mock( "http response", :code => '404', :message => "Not found", :each_capitalized => {} )
			@http.stub( :request ).and_return( response )
			response.stub( :value ).
				and_raise( Net::HTTPNotFound::EXCEPTION_TYPE.new("404 Not Found", response) )

			expect {
				@camera.video_status( 2 )
			}.to raise_exception( NotImplementedError, /videostatus/ )
		end

	end



	context "with a networked camera", :config_exists => true do

		before( :all ) do
			config = load_camera_config()
			options = config.values_at( 'host', 'username', 'password' )
			@camera = Axis::Camera.new( *options )
		end


		it "can fetch the full firmware release id of the camera" do
			@camera.firmware_release.should =~ /^id-\d+-\d+\.\d+-\d+$/i
		end

		it "can fetch the firmware release version from the camera" do
			@camera.firmware_version.should =~ /^\d+\.\d+$/i
		end

		it "can fetch the camera model" do
			@camera.model.should =~ /^AXIS/i
		end

		it "can fetch the camera's serial number" do
			@camera.serial_number.should =~ /^\w+$/i
		end

		it "can fetch the camera's server report as a hash" do
			@camera.server_report.should include( :settings_for_eth0, :server_report_start, 
				:network_statistics, :uptime, :etc_release, :network_configuration, 
				:proc_meminfo, :var_log_messages, :usr_share_axis_release_variables, 
				:routing_table, :vmstatus, :kernel, :ipv6_routing_table, 
				:filesystems_status, :access_log, :multicast_groups, :server_report_end, 
				:snapshot_of_the_current_processes, :network_connections, :system_information )
		end

		it "can fetch the camera's serial number" do
			@camera.serial_number.should =~ /^\w+$/i
		end

		it "can fetch the camera's axis release variables as a Hash" do
			rval = @camera.axis_release_variables

			rval.should be_a( Hash )
			rval.should include( :release, :build, :buildtime, :part, :fs_type_part_rootfs,
			 	:fs_type_part_rwfs, :mopts_part_rwfs )
		end


		context "user management" do

			before( :each ) do
				@test_user = 'unittest'
				@test_password = 'foo,Kind!'
			end

			it "can fetch a list of users" do
				res = @camera.users
				res.should be_a( Hash )
				res.should include( 'root' => ['root'] )
			end
		end


		context "image and video" do

			it "can fetch the default height and width of the camera" do
				res = @camera.image_size

				res.should be_an( Array )
				res.should have( 2 ).members
				res[0].should be_a( Integer )
				res[1].should be_a( Integer )
			end

			it "can fetch the default height and width of the second camera" do
				res = nil

				# Depending on the target camera, this should either be a valid response
				# or an Axis::ParameterError if there isn't a second camera.
				begin
					res = @camera.image_size( 2 )
				rescue Axis::ParameterError => err
					err.should be_an( Axis::ParameterError )
					err.message.should =~ /error getting image params/i
				else
					res.should be_an( Array )
					res.should have( 2 ).members
					res[0].should be_a( Integer )
					res[1].should be_a( Integer )
				end
			end

			it "can fetch the video status of the first video source" do
				pending "this currently just 404s, despite being documented in the API docs" do
					@camera.video_status.should be_true()
				end
			end

			it "can fetch a bitmap image from the default camera at the default resolution"

		end

	end

end

