Events::Application.routes.draw do

  resources :preferences
  resources :exclusions
  resources :hunks
  # Imported from previous project vvv
  resources :roles do
    member do
      get :rights
      post :right_add
      post :right_remove
    end
  end

  resources :rights

  resources :users do
    member do
      get :roles
      post :role_add
      post :role_remove
    end
    collection do
      get :logon
      get :logoff
      post :do_logon
    end
  end
  
  resources :sessions
  # Imported from previous project ^^^

  resources :displays

  resources :jobs do
    member do
      get 'test'
    end
  end

  resources :alerts do
    collection do
      get 'ackall'
    end
    member do
      get 'acknowledge'
    end
    resources :comments, shallow: true
  end

  resources :statistics

  resources :searches

  resources :services

  resources :systems

  resources :events do
    collection do 
      get :search
    end
  end
  
  resources :comments, :only => [:index]

  resources :positions

  resources :words

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  root 'events#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
