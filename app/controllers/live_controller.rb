class LiveController < ChunkedController
  include StreamingSupport

  private

  def stream_data(stream)
    chunked do |stream|
      super stream
      raise "Simulated error"
    end
  end
end
