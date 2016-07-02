Rails.application.routes.draw do
  get 'chunked/private_response'
  get 'chunked/public_response'
  get 'live/private_response'
  get 'live/public_response'

  devise_for :users
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
