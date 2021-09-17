require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/redis"
require "logstash/json"
require "redis"
require "flores/random"

describe LogStash::Outputs::Redis do

  context "integration tests", :integration => true do
    RSpec.shared_examples "writing to redis" do |extra_config|
      let(:key) { 10.times.collect { rand(10).to_s }.join("") }
      let(:event_count) { Flores::Random.integer(0..10000) }
      let(:message) { Flores::Random.text(0..100) }
      let(:default_config) {
        {
          "key" => key,
          "data_type" => data_type,
          "host" => "localhost"
        }
      }
      let(:redis_config) {
        default_config.merge(extra_config || {})
      }

      let(:redis_output) { described_class.new(redis_config) }

      before do
        redis_output.register
        # TODO:
        puts "#{data_type} => #{event_count}"

        event_count.times do |i|
          event = LogStash::Event.new("sequence" => i, "message" => message)
          redis_output.receive(event)
        end
        redis_output.close
      end

      it "should successfully send all events to redis" do
        redis = Redis.new(:host => "127.0.0.1")

        # The list should contain the number of elements our agent pushed up.
        case data_type
        when "list"
          expect(redis.llen(key)).to eql event_count
          # Now check all events for order and correctness.
          event_count.times do |value|
            id, element = redis.blpop(key, 0)
            event = LogStash::Event.new(LogStash::Json.load(element))
            expect(event.get("sequence")).to eql value
            expect(event.get("message")).to eql message
          end
        # The list should now be empty
          expect(redis.llen(key)).to eql 0

        when "set"
          expect(redis.scard(key)).to eql event_count
          event_count.times { |value| expect(redis.sismember(key,value)).to be_truthy }
        end
      end
    end

    set_config = { "set_value" => "%{sequence}" }

    context "when batch_mode is false list" do
      context "when data_type is list" do
        let(:data_type) { "list" }
        include_examples "writing to redis"
      end

      context "when data_type is set" do
        let(:data_type) { "set" }
        include_examples "writing to redis", set_config
      end
    end

    context "when batch_mode is true " do
      batch_events = Flores::Random.integer(1..1000)
      batch_settings = {
        "batch" => true,
        "batch_events" => batch_events
      }

      context "when data_type is list" do
        let(:data_type) { "list" }

        include_examples "writing to redis", batch_settings do

          # A canary to make sure we're actually enabling batch mode
          # in this shared example.
          it "should have batch mode enabled" do
            expect(redis_config).to include("batch")
            expect(redis_config["batch"]).to be_truthy
          end
        end
      end

      context "when data_type is set" do
        let(:data_type) { "set" }

        include_examples "writing to redis", batch_settings.merge(set_config) do
          # A canary to make sure we're actually enabling batch mode
          # in this shared example.
          it "should have batch mode enabled" do
            expect(redis_config).to include("batch")
            expect(redis_config["batch"]).to be_truthy
          end
        end
      end
    end
  end
end
