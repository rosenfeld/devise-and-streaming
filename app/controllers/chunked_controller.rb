class ChunkedController < ApplicationController
  before_action :authenticate_user!, only: :private_response
  before_action :set_chunked_headers

  def private_response
    public_response
  end

  def public_response
    stream_data response.stream
  end

  private

  def set_chunked_headers
    response.headers['Cache-Control'] = 'no-cache' # skip Rack::ETag middleware
    response.headers['Content-Type'] = 'text/plain; charset=utf-8'
  end

  def stream_data(stream)
    3.times{|i|
      # We write a big chunk so that we can also see the streaming happening on Chrome.
      # Otherwise we'd have to check with curl or some similar tool.
      stream.write "big chunked line #{i}" * 100 + "\n\n"
      sleep 1
    }
  end
end
