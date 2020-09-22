module ToolingInvoker
  class Job
    attr_reader :id, :language, :s3_uri, :exercise, :container_version, :execution_timeout
    attr_accessor :status, :output, :context, :invocation_data

    def initialize(id, language, exercise, s3_uri, container_version, execution_timeout)
      @id = id
      @language = language
      @exercise = exercise
      @s3_uri = s3_uri
      @container_version = container_version
      @execution_timeout = execution_timeout
      @status = 410
      @context = {}
      @invocation_data = {}
    end

    def to_h
      {
        status: status,
        output: output,
        context: context,
        invocation_data: invocation_data
      }
    end
  end
end
