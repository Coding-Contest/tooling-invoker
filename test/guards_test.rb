require 'test_helper'

module ToolingInvoker
  class GuardsTest < Minitest::Test
    def setup
      super
      @job_id = SecureRandom.hex
      @hex = SecureRandom.hex

      SecureRandom.stubs(hex: @hex)

      @job_dir = "#{Configuration.instance.jobs_dir}/#{@job_id}-#{@hex}"
      @input_efs_dir = "#{Configuration.instance.jobs_efs_dir}/#{@job_id}"

      FileUtils.mkdir_p(@input_efs_dir)
    end

    def teardown
      FileUtils.rm_rf(@job_dir)
      FileUtils.rm_rf(@input_efs_dir)
    end

    def test_timeout
      job = Jobs::TestRunnerJob.new(
        @job_id,
        "ruby", "bob", "v1",
        1 # This is the timeout that we use to test this
      )
      ExecDocker.any_instance.stubs(docker_run_command: "#{__dir__}/bin/infinite_loop")

      # Check the cleanup command is called correctly and then
      # store it so we can clean up the test too. Else we'll leave
      # the infinite loop running, and your laptop battery will die.
      pid_to_kill = nil
      Process.expects(:kill).with do |signal, pid|
        assert_equal "KILL", signal
        assert pid
        pid_to_kill = pid
      end

      begin
        InvokeDocker.(job)
      ensure
        `kill -s SIGKILL #{pid_to_kill}`
      end

      assert_equal Jobs::Job::TIMEOUT_STATUS, job.status
    end

    def test_too_many_results
      job = Jobs::TestRunnerJob.new(
        @job_id,
        "ruby", "bob", "v1",
        1 # This is the timeout that we use to test this
      )
      ExecDocker.any_instance.stubs(docker_run_command: "#{__dir__}/bin/infinite_loop")

      FileUtils.mkdir_p(job.source_code_dir)
      Dir.chdir(job.source_code_dir) do
        File.write(
          "results.json",
          "a" * (Jobs::Job::MAX_OUTPUT_FILE_SIZE + 1)
        )
      end

      assert_equal Jobs::Job::EXCESSIVE_OUTPUT_STATUS, job.status
    end

    def test_excessive_output
      job = Jobs::TestRunnerJob.new(
        @job_id,
        "ruby", "bob", "v1",
        1 # Ensures this is high enough to run out of output
      )
      ExecDocker.any_instance.stubs(docker_run_command: "#{__dir__}/bin/infinite_output")

      # The command will print out 20,000 bytes. Let's break at
      # the half way stage.
      ExecDocker.any_instance.stubs(output_limit: 10_000)

      InvokeDocker.(job)

      assert_equal Jobs::Job::EXCESSIVE_STDOUT_STATUS, job.status
    end
  end
end
