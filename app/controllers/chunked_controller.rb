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
      stream.write "chunked line #{i}\n"
      sleep 0.5
    }
    stream.close
  end
end
