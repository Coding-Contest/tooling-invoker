module ToolingInvoker
  class CheckCanary
    include Mandate

    def call
      # Wait for the the machine to be ready
      WaitForManager.()
      CreateNetworks.()

      # Do the job three times here as a guard.
      # Quick fail if we get 512 or 513 which means something bad.
      # Quick succeed if we get a 200.
      # Otherwise see if we recover.
      3.times do
        job = Jobs::TestRunnerJob.new(
          "canary-#{SecureRandom.hex}",
          'ruby',
          'hello-world',
          CANARY_SOURCE,
          '1'
        )
        ProcessJob.(job)

        return true if job.status == 200
        return false if job.status == 512
        return false if job.status == 513

        sleep(5)
      end

      false
    end

    CANARY_SOURCE = {
      'submission_efs_root' => "cb5a174a13494e3a8aa556bc5097b7e2",
      'submission_filepaths' => ["hello_world.rb"],
      'exercise_git_repo' => "ruby",
      'exercise_git_sha' => "508219b5722e3d5b678299159ceb396349cc0b25",
      'exercise_git_dir' => "exercises/practice/hello-world",
      'exercise_filepaths' => [
        "hello_world_test.rb"
      ]
    }.freeze
  end
end