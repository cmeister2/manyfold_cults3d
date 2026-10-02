# frozen_string_literal: true

ManyfoldCults3d::Engine.routes.draw do
  root to: "manyfold_cults3d/status#index"
  get "import", to: "manyfold_cults3d/imports#new", as: :import
  post "import", to: "manyfold_cults3d/imports#create"
  post "library_models/:id/create_model", to: "manyfold_cults3d/library_models#create_model", as: :create_model
  get "link", to: "manyfold_cults3d/links#new", as: :link
  post "link", to: "manyfold_cults3d/links#create"
end
