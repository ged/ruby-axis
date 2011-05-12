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
	end

	after( :all ) do
		reset_logging()
	end


	it "bases its endpoint URL on the host it's created with" do
		Axis::Camera.new( 'outside-camera.example.com' ).endpoint.should ==
			URI( 'http://outside-camera.example.com/axis-cgi' )
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

