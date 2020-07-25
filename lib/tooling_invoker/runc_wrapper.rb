module ToolingInvoker
  class RuncWrapper

    def initialize(job_dir, configuration, execution_timeout: 5)
      @run_id = SecureRandom.hex

      @job_dir = job_dir
      @configuration = configuration
      @execution_timeout = execution_timeout.to_i

      @binary_path = "/opt/container_tools/runc"
      @suppress_output = false
      @memory_limit = 3000000
    end

    def run!
      File.write("#{job_dir}/config.json", configuration.to_json)

      actual_command = "#{binary_path} --root root-state run #{run_id}"
      run_cmd = ExternalCommand.new(
        "bash -x -c 'ulimit -v #{memory_limit}; #{actual_command}'",
        timeout: execution_timeout,
        output_limit: 1024*1024
      )

      begin
        Dir.chdir(job_dir) do
          kill_thread = Thread.new do
            sleep(execution_timeout)
            system("#{binary_path} --root root-state kill #{run_id} KILL")
          end

          begin
            run_cmd.()
          rescue => e
            p "Errored: #{e}"
          end

          kill_thread.kill
        end
      rescue
      end

      run_cmd.to_h
    rescue => e
      p e
      {}
    end

    private
    attr_reader :binary_path, :suppress_output, :memory_limit, :execution_timeout, :job_dir, :configuration, :run_id
  end
end

