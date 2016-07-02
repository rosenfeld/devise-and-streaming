class ChunkedController < ApplicationController
  before_action :authenticate_user!, only: :private_response

  def private_response
  end

  def public_response
  end
end
