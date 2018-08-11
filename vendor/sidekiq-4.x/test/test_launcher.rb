# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/launcher'

class TestLauncher < Sidekiq::Test

  describe 'launcher' do
    before do
      Sidekiq.redis {|c| c.flushdb }
    end

    def new_manager(opts)
      Sidekiq::Manager.new(opts)
    end

    describe 'heartbeat' do
      before do
        @mgr = new_manager(options)
        @launcher = Sidekiq::Launcher.new(options)
        @launcher.manager = @mgr
        @id = @launcher.identity

        Sidekiq::Processor::WORKER_STATE['a'] = {'b' => 1}

        @proctitle = $0
      end

      after do
        Sidekiq::Processor::WORKER_STATE.clear
        $0 = @proctitle
      end

      it 'fires new heartbeat events' do
        i = 0
        Sidekiq.on(:heartbeat) do
          i += 1
        end
        assert_equal 0, i
        @launcher.heartbeat
        assert_equal 1, i
        @launcher.heartbeat
        assert_equal 1, i
      end

      describe 'when manager is active' do
        before do
          Sidekiq::CLI::PROCTITLES << proc { "xyz" }
          @launcher.heartbeat
          Sidekiq::CLI::PROCTITLES.pop
        end

        it 'sets useful info to proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] xyz", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget(@id, 'busy') }
          assert_equal ["1"], info
          expires = Sidekiq.redis { |c| c.pttl(@id) }
          assert_in_delta 60000, expires, 500
        end
      end

      describe 'when manager is stopped' do
        before do
          @launcher.quiet
          @launcher.heartbeat
        end

        #after do
          #puts system('redis-cli -n 15 keys  "*" | while read LINE ; do TTL=`redis-cli -n 15 ttl "$LINE"`; if [ "$TTL" -eq -1 ]; then echo "$LINE"; fi; done;')
        #end

        it 'indicates stopping status in proctitle' do
          assert_equal "sidekiq #{Sidekiq::VERSION} myapp [1 of 3 busy] stopping", $0
        end

        it 'stores process info in redis' do
          info = Sidekiq.redis { |c| c.hmget(@id, 'busy') }
          assert_equal ["1"], info
          expires = Sidekiq.redis { |c| c.pttl(@id) }
          assert_in_delta 60000, expires, 50
        end
      end
    end

    def options
      { :concurrency => 3, :queues => ['default'], :tag => 'myapp' }
    end

  end
end
