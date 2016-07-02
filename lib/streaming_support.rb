module StreamingSupport
#  extend ActiveSupport::Concern # required for it to work in Rails 5
#  include ActionController::Live
#  # Alternatively:
#  # def self.included(base)
#  #   base.include ActionController::Live
#  # end
#
# Work-around for handling unauthenticated requests with ActionController::Live:
#  def process(*args)
#    super
#  rescue UncaughtThrowError => e
#    throw :warden if e.message == 'uncaught throw :warden'
#    raise e
#  end

  # A cleaner alternative, by providing a 'chunked' call whenever streaming is desired.
  # In that case, the thread would be spawned just after the before/around hooks.
  # However, this approach may have problems with after hooks if they exist.
  def self.included(base)
    base.extend ActionController::Live::ClassMethods
    # Alternatively, if your application does not support non-streamed responses (they would
    # timeout for example):
#    def base.make_response!(request)
#      raise 'HTTP/1.0 is not supported' if request.get_header('HTTP_VERSION') == 'HTTP/1.0'
#      ActionController::Live::Response.new.tap do |res|
#        res.request = request
#      end
#    end
  end

  def chunked(&block)
    response.commit!
    Thread.start do
      begin
        yield response.stream
      rescue Exception => e
        log_error "Streamed request thread raised", e
      ensure
        response.stream.close
      end
    end
  end

  def log_error(message, exception)
    logger.fatal do
      message = "#{message}: #{exception.class} (#{exception.message}):\n"
      message << exception.annoted_source_code.to_s if exception.respond_to?(:annoted_source_code)
      message << "  " << exception.backtrace.join("\n  ")
      "#{message}\n\n"
    end
  end
end
