class LiveController < ChunkedController
  include StreamingSupport

  private

  def stream_data(stream)
    chunked do
      super
      raise "Simulated error"
    end
  end
end
