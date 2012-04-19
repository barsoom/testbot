require File.expand_path(File.join(File.dirname(__FILE__), 'runner.rb'))
require 'iconv'

module Testbot::Runner
  class Job
    attr_reader :root, :project, :build_id

    def initialize(runner, id, build_id, project, root, type, ruby_interpreter, files)
      @runner, @id, @build_id, @project, @root, @type, @ruby_interpreter, @files =
        runner, id, build_id, project, root, type, ruby_interpreter, files
    end

    def jruby?
      @ruby_interpreter == 'jruby'
    end

    def run(instance)
      return if @killed
      puts "Running job #{@id} (build #{@build_id})... "
      test_env_number = (instance == 0) ? '' : instance + 1
      base_environment = "export RAILS_ENV=test; export TEST_ENV_NUMBER=#{test_env_number}; cd #{@project};"

      adapter = Adapter.find(@type)
     
      result, run_time = "", 0
      retry_tests_when_failing do 
        result = "\n#{`hostname`.chomp}:#{Dir.pwd}\n"
        run_time = measure_run_time do
          result += run_and_return_result("#{base_environment} #{adapter.command(@project, ruby_cmd, @files)}")
        end
      end

      Server.put("/jobs/#{@id}", :body => { :result => strip_invalid_utf8(result), :success => success?, :time => run_time })
      puts "Job #{@id} finished."
    end

    def kill!(build_id)
      if @build_id == build_id && @test_process
        # The child process that runs the tests is a shell, we need to kill it's child process
        system("pkill -KILL -P #{@test_process.pid}")
        @killed = true
      end
    end

    private

    def retry_tests_when_failing
      yield
      yield unless success?
    end

    def strip_invalid_utf8(text)
      # http://po-ru.com/diary/fixing-invalid-utf-8-in-ruby-revisited/
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      ic.iconv(text + ' ')[0..-2]
    end

    def measure_run_time
      start_time = Time.now
      yield
      (Time.now - start_time) * 100
    end

    def run_and_return_result(command)
      @test_process = open("|#{command} 2>&1", 'r')
      output = @test_process.read
      @test_process.close
      output
    end

    def success?
      $?.exitstatus == 0
    end

    def ruby_cmd
      if @ruby_interpreter == 'jruby' && @runner.config.jruby_opts
        'jruby ' + @runner.config.jruby_opts
      else
        @ruby_interpreter
      end
    end
  end
end
