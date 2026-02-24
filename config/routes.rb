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
  post "schema/analyze_table", to: "schema#analyze_table", as: :analyze_table

  get "console", to: "console#index", as: :console_index
  post "console/execute", to: "console#execute", as: :console_execute
end
