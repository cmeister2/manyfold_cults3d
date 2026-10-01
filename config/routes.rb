# frozen_string_literal: true

ManyfoldMyminifactory::Engine.routes.draw do
  root to: "manyfold_myminifactory/status#index"
  get "import", to: "manyfold_myminifactory/imports#new", as: :import
  post "import", to: "manyfold_myminifactory/imports#create"
  get "link", to: "manyfold_myminifactory/links#new", as: :link
  post "link", to: "manyfold_myminifactory/links#create"
end
