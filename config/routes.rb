# frozen_string_literal: true

RailsDbInspector::Engine.routes.draw do
  root to: "queries#index"

  resources :queries, only: %i[index show] do
    member do
      get :explain
    end

    collection do
      post :clear
    end
  end

  get "schema", to: "schema#index", as: :schema_index
end
