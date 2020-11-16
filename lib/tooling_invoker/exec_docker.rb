require 'open3'

module ToolingInvoker
  class ExecDocker
    include Mandate

    BLOCK_SIZE = 1024
    ONE_MEGABYTE_IN_BYTES = 1_024 * 1_024

    def initialize(job)
      @job = job
      @timeout_s = job.timeout_s.to_i
      @timeout_s = 20 unless @timeout_s > 0

      @container_label = "exercism-#{job.id}-#{SecureRandom.hex}"
      @output_limit = ONE_MEGABYTE_IN_BYTES
    end

    def call
      # We run the command in a thread and have another thread dedicated
      # to timeouts. This is in addition to the internal timeout command
      # that we use. We also want to look out for (and rescue)
      # various failed exit conditions (timeout, out of memory, etc)
      begin
        docker_thread = Thread.new do
          start_time = Time.now.to_f
          exec_command!
          puts "#{job.id}: Docker time: #{Time.now.to_f - start_time}"
        end

        # Run the command in a thread and timeout just
        # after the SIGKILL is sent inside ExternalCommand timeout.
        # Note whether it existed cleanly (success) or timed out
        success = docker_thread.join(timeout_s + 1.1)

        # If we get to this stage, and the thread didn't exit
        # clearly, it's still running and we need to stop it
        # We do this in two stages. First we call abort!, which
        # should clean up the service. Then we kill the actual thread.
        # This potentially orphans the child process. Getting here is
        # very unlikely as it means that the system level timeout has been
        # breached, but it just adds one tiny layer of protection.
        unless success
          puts "Forcing timeout"
          job.timed_out!

          abort!
          sleep(0.01)
          docker_thread.kill
        end
      rescue StandardError => e
        job.exceptioned!(e.message, e.backtrace)
      end

      # Always explicity kill the containers in case they've timed-out
      # via out manual checks.
      kill_containers!
    end

    private
    attr_reader :job, :container_label, :timeout_s, :output_limit, :pid

    def exec_command!
      captured_stdout = []
      captured_stderr = []

      stdin, stdout, stderr, wait_thr = Open3.popen3(docker_run_command)
      @pid = wait_thr[:pid]

      stdin.close_write

      begin
        while wait_thr.alive?
          break if stdout.closed?
          break if stderr.closed?

          files = IO.select([stdout, stderr])
          next unless files

          files[0].each do |f|
            if f.closed?
              job.killed_for_excessive_output!
              return # rubocop:disable Lint/NonLocalExitFromIterator
            end

            stream = f == stdout ? captured_stdout : captured_stderr
            begin
              stream << f.read_nonblock(BLOCK_SIZE)
            rescue IOError
              # Don't blow up if there is an error reading
              # the stream.
            end

            # If we haven't got too much output then continue for
            # another cycle. Our measure is the amount of blocks
            # we've collected over the total data we want.
            next unless output_limit.positive?
            next unless stream.size > (output_limit.to_f / BLOCK_SIZE)

            # If there is too much output, kill the process.
            abort!

            job.killed_for_excessive_output!
            return # rubocop:disable Lint/NonLocalExitFromIterator
          end
        end
      ensure
        stdout.close unless stdout.closed?
        stderr.close unless stderr.closed?

        job.stdout = fix_encoding(captured_stdout.join)
        job.stderr = fix_encoding(captured_stdout.join)

        if wait_thr.value&.exitstatus == 0
          job.succeeded!
        elsif wait_thr.value.termsig == 9
          job.timed_out!
        else
          job.exceptioned!("Exit status: #{wait_thr.value&.exitstatus}")
        end

        # TODO: Remove this at some point
        File.write("#{job.output_dir}/stdout", job.stdout)
        File.write("#{job.output_dir}/stderr", job.stderr)
      end
    end

    def abort!
      Process.kill("KILL", pid)
    rescue StandardError
      # If the process has already gone, then don't
      # stress out. We'll already be raise a 401
      # downstream of here.
    end

    def kill_containers!
      # Always kill the container in case it's still running
      # TODO: Check if its running first
      cmd = [
        "docker container ls",
        "--filter='label=#{container_label}'",
        "-q"
      ].join(" ")
      stdout, = Open3.capture2(cmd)
      stdout.split.each do |container_id|
        system("docker kill #{container_id}")
      end
    end

    memoize
    def docker_run_command
      docker_cmd = [
        "docker container run",
        "-a stdout -a stderr", # Attach stdout and stderr
        "-v #{job.source_code_dir}:/mnt/exercism-iteration",
        "-l #{container_label}",
        "-m 3GB",
        "--stop-timeout 0", # Convert a SIGTERM to a SIGKILL instantly
        "--rm",
        "--network none",
        job.image,
        job.exercise, # TODO: These should be read from invocation_args
        "/mnt/exercism-iteration/",
        "/mnt/exercism-iteration/"
      ].join(" ")

      timeout_cmd = "/usr/bin/timeout -s SIGTERM -k 1 #{timeout_s} #{docker_cmd}"
      Exercism.env.development? ? docker_cmd : timeout_cmd
    end

    def fix_encoding(text)
      return "" if text.nil?

      text.force_encoding("ISO-8859-1").encode("UTF-8")
    rescue StandardError => e
      puts e.message
      puts e.backtrace
      puts "--- failed to encode as UTF-8: #{e.message} ---"
      ""
    end
  end
end
