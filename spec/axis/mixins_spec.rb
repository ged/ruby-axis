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

describe Axis, "mixin" do

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end


	describe Axis::HashUtilities do
		it "includes a function for stringifying Hash keys" do
			testhash = {
				:foo => 1,
				:bar => {
					:klang => 'klong',
					:barang => { :kerklang => 'dumdumdum' },
				}
			}

			result = Axis::HashUtilities.stringify_keys( testhash )

			result.should be_an_instance_of( Hash )
			result.should_not be_equal( testhash )
			result.should == {
				'foo' => 1,
				'bar' => {
					'klang' => 'klong',
					'barang' => { 'kerklang' => 'dumdumdum' },
				}
			}
		end


		it "includes a function for symbolifying Hash keys" do
			testhash = {
				'foo' => 1,
				'bar' => {
					'klang' => 'klong',
					'barang' => { 'kerklang' => 'dumdumdum' },
				}
			}

			result = Axis::HashUtilities.symbolify_keys( testhash )

			result.should be_an_instance_of( Hash )
			result.should_not be_equal( testhash )
			result.should == {
				:foo => 1,
				:bar => {
					:klang => 'klong',
					:barang => { :kerklang => 'dumdumdum' },
				}
			}
		end

		it "includes a function that can be used as the key-collision callback for " +
		   "Hash#merge that does recursive merging" do
			hash1 = {
				:foo => 1,
				:bar => [:one],
				:baz => {
					:glom => [:chunker]
				}
			}
			hash2 = {
				:klong => 88.8,
				:bar => [:locke],
				:baz => {
					:trim => :liquor,
					:glom => [:plunker]
				}
			}

			hash1.merge( hash2, &Axis::HashUtilities.method(:merge_recursively) ).should == {
				:foo => 1,
				:bar => [:one, :locke],
				:baz => {
					:glom => [:chunker, :plunker],
					:trim => :liquor,
				},
				:klong => 88.8,
			}
		end

	end


	describe Axis::ArrayUtilities do

		it "includes a function for stringifying Array elements" do
			testarray = [:a, :b, :c, [:d, :e, [:f, :g]]]

			result = Axis::ArrayUtilities.stringify_array( testarray )

			result.should be_an_instance_of( Array )
			result.should_not be_equal( testarray )
			result.should == ['a', 'b', 'c', ['d', 'e', ['f', 'g']]]
		end


		it "includes a function for symbolifying Array elements" do
			testarray = ['a', 'b', 'c', ['d', 'e', ['f', 'g']]]

			result = Axis::ArrayUtilities.symbolify_array( testarray )

			result.should be_an_instance_of( Array )
			result.should_not be_equal( testarray )
			result.should == [:a, :b, :c, [:d, :e, [:f, :g]]]
		end
	end


end