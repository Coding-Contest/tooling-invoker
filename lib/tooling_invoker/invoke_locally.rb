module ToolingInvoker
  class InvokeLocally
    include Mandate

    def initialize(job)
      @job = job
    end

    def call
      tool_dir = "#{config.containers_dir}/#{job.tool}"
      job_dir = "#{config.jobs_dir}/#{job.id}-#{SecureRandom.hex}"
      input_dir = "#{job_dir}/input"
      output_dir = "#{job_dir}/output"
      FileUtils.mkdir_p(input_dir)
      FileUtils.mkdir_p(output_dir)

      SyncS3.(job.s3_uri, input_dir)

      cmd = "/bin/sh bin/run.sh #{job.exercise} #{input_dir} #{output_dir}"
      exit_status = Dir.chdir(tool_dir) do
        system(cmd)
      end

      job.context = {
        tool_dir: tool_dir,
        job_dir: job_dir,
        stdout: '',
        stderr: ''
      }
      job.invocation_data = {
        cmd: cmd,
        exit_status: exit_status
      }
      job.result = File.read("#{output_dir}/#{job.results_filepath}")
      job.status = job.result ? 200 : 400
    end

    private
    attr_reader :job

    def config
      ToolingInvoker.config
    end
  end
end
