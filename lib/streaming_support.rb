module StreamingSupport
  extend ActiveSupport::Concern # required for it to work in Rails 5
  include ActionController::Live
  # Alternatively:
  # def self.included(base)
  #   base.include ActionController::Live
  # end

  def process(*args)
    super
  rescue UncaughtThrowError => e
    throw :warden if e.message == 'uncaught throw :warden'
    raise e
  end
end
