# frozen_string_literal: true

require 'sidekiq/web'
require 'sidekiq-scheduler/web'

Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: 'letter_opener' if Rails.env.development?

  authenticate :user, lambda { |u| u.admin? } do
    mount Sidekiq::Web, at: 'sidekiq', as: :sidekiq
    mount PgHero::Engine, at: 'pghero', as: :pghero
    mount AdminScript::Engine, at: 'admin_scripts', as: :admin_scripts
  end

  use_doorkeeper do
    controllers authorizations: 'oauth/authorizations', authorized_applications: 'oauth/authorized_applications'
  end

  get '.well-known/host-meta', to: 'well_known/host_meta#show', as: :host_meta, defaults: { format: 'xml' }
  get '.well-known/webfinger', to: 'well_known/webfinger#show', as: :webfinger

  devise_for :users, path: 'auth', controllers: {
    sessions:           'auth/sessions',
    registrations:      'auth/registrations',
    passwords:          'auth/passwords',
    confirmations:      'auth/confirmations',
    omniauth_callbacks: 'auth/omniauth_callbacks',
  }

  devise_scope :user do
    with_devise_exclusive_scope('/auth', :user, {}) do
      resource :oauth_registration, only: [:new, :create],
        path: 'oauth/oauth_registrations'
    end
  end

  get '/@:username', to: 'accounts#show', as: :short_account
  get '/@:account_username/:id', to: 'statuses#show', as: :short_account_status

  get '/users/:username', to: redirect('/@%{username}'), constraints: { format: :html }

  resources :accounts, path: 'users', only: [:show], param: :username do
    resources :stream_entries, path: 'updates', only: [:show] do
      member do
        get :embed
      end
    end

    get :remote_follow,  to: 'remote_follow#new'
    post :remote_follow, to: 'remote_follow#create'

    resources :media, only: [:index], controller: :medium_accounts
    resources :followers, only: [:index], controller: :follower_accounts
    resources :following, only: [:index], controller: :following_accounts
    resource :follow, only: [:create], controller: :account_follow
    resource :unfollow, only: [:create], controller: :account_unfollow
  end

  namespace :settings do
    resources :oauth_authentications, only: [:index, :destroy]
    resource :profile, only: [:show, :update]
    resource :preferences, only: [:show, :update]
    resource :import, only: [:show, :create]

    resource :export, only: [:show]
    namespace :exports, constraints: { format: :csv } do
      resources :follows, only: :index, controller: :following_accounts
      resources :blocks, only: :index, controller: :blocked_accounts
      resources :mutes, only: :index, controller: :muted_accounts
    end

    resource :two_factor_authentication, only: [:show, :create, :destroy]
    namespace :two_factor_authentication do
      resources :recovery_codes, only: [:create]
      resource :confirmation, only: [:new, :create]
    end

    resource :follower_domains, only: [:show, :update]
  end

  resources :media, only: [:show]
  resources :tags,  only: [:show]
  resources :oauth_authentications, only: [:show], param: :uid

  namespace :intent do
    resources :statuses, only: :new
  end

  # Remote follow
  resource :authorize_follow, only: [:show, :create]

  namespace :admin do
    resources :pubsubhubbub, only: [:index]
    resources :domain_blocks, only: [:index, :new, :create, :show, :destroy]
    resource :settings, only: [:edit, :update]
    resources :instances, only: [:index]
    resources :suggestion_tags, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :trend_ng_words, only: [:index, :new, :create, :edit, :update, :destroy]
    resources :oauth_authentications, only: [:destroy]

    resources :reports, only: [:index, :show, :update] do
      resources :reported_statuses, only: [:update, :destroy]
    end

    resources :accounts, only: [:index, :show] do
      resource :reset, only: [:create]
      resource :silence, only: [:create, :destroy]
      resource :suspension, only: [:create, :destroy]
      resource :confirmation, only: [:create]
      resources :statuses, only: [:index, :update, :destroy]
    end

    resources :users, only: [] do
      resource :two_factor_authentication, only: [:destroy]
    end
  end

  get '/admin', to: redirect('/admin/settings/edit', status: 302)

  namespace :api do
    # PubSubHubbub outgoing subscriptions
    resources :subscriptions, only: [:show]
    post '/subscriptions/:id', to: 'subscriptions#update'

    # PubSubHubbub incoming subscriptions
    post '/push', to: 'push#update', as: :push

    # Salmon
    post '/salmon/:id', to: 'salmon#update', as: :salmon

    # OEmbed
    get '/oembed', to: 'oembed#show', as: :oembed

    # ActivityPub
    namespace :activitypub do
      get '/users/:id/outbox', to: 'outbox#show', as: :outbox
      get '/statuses/:id', to: 'activities#show_status', as: :status
      resources :notes, only: [:show]
    end

    # JSON / REST API
    namespace :v1 do
      resources :statuses, only: [:create, :show, :destroy] do
        member do
          get :context
          get :card
          get :reblogged_by
          get :favourited_by

          post :reblog
          post :unreblog
          post :favourite
          post :unfavourite
          post :mute
          post :unmute
        end
      end

      namespace :timelines do
        resource :home, only: :show, controller: :home
        resource :public, only: :show, controller: :public
        resources :tag, only: :show
      end

      get '/search', to: 'search#index', as: :search
      get '/search/statuses/:query', to: 'search#statuses', as: :status_search_timeline

      resource :push_notification_preferences, only: [:show, :update]
      resources :trend_tags, only: [:index]
      resources :follows,    only: [:create]
      resources :media,      only: [:create]
      resources :apps,       only: [:create]
      resources :blocks,     only: [:index]
      resources :mutes,      only: [:index]
      resources :favourites, only: [:index]
      resources :reports,    only: [:index, :create]
      resources :pixiv_twitter_images, only: [:create]
      resources :firebase_cloud_messaging_tokens, only: [:create, :destroy], param: :platform
      resources :suggested_accounts, only: [:index]
      resources :oauth_authentications, only: [:show], param: :uid

      resource :instance,      only: [:show]
      resource :domain_blocks, only: [:show, :create, :destroy]

      resources :follow_requests, only: [:index] do
        member do
          post :authorize
          post :reject
        end
      end

      resources :notifications, only: [:index, :show] do
        collection do
          post :clear
          post :dismiss
        end
      end

      resources :accounts, only: [:show] do
        collection do
          get :relationships
          get :verify_credentials
          patch :update_credentials
          get :search
        end

        member do
          get :statuses
          get :followers
          get :following

          post :follow
          post :unfollow
          post :block
          post :unblock
          post :mute
          post :unmute
        end
      end
    end

    namespace :web do
      resource :settings, only: [:update]
    end
  end

  get '/web/(*any)', to: 'home#index', as: :web

  get '/about',      to: 'about#show'
  get '/about/more', to: 'about#more'
  get '/terms',      to: 'about#terms'
  get '/app_terms',  to: 'about#app_terms'
  get '/app_eula',   to: 'about#app_eula'

  root 'home#index'

  match '*unmatched_route',
    via: :all,
    to: 'application#raise_not_found',
    format: false
end
