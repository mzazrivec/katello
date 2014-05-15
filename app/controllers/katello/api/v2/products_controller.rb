#
# Copyright 2014 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

module Katello
  class Api::V2::ProductsController < Api::V2::ApiController

    before_filter :find_organization, :only => [:create]
    before_filter :find_product, :only => [:update, :destroy, :show, :sync]

    resource_description do
      api_version "v2"
    end

    def_param_group :product do
      param :description, String, :desc => N_("Product description")
      param :gpg_key_id, :number, :desc => N_("Identifier of the GPG key")
      param :sync_plan_id, :number, :desc => N_("Plan numeric identifier"), :allow_nil => true
    end

    api :GET, "/products", N_("List products")
    api :GET, "/subscriptions/:subscription_id/products", N_("List of subscription products in an organization")
    api :GET, "/organizations/:organization_id/products", N_("List of products in an organization")
    param :organization_id, :number, :desc => N_("Filter products by organization"), :required => true
    param :subscription_id, :identifier, :desc => N_("Filter products by subscription")
    param :name, String, :desc => N_("Filter products by name")
    param :enabled, :bool, :desc => N_("Filter products by enabled or disabled")
    param_group :search, Api::V2::ApiController
    def index
      options = {
        :filters => [],
        :load_records? => true
      }

      ids = Product.readable.pluck(:id)
      ids = filter_by_subscription(ids, params[:subscription_id]) if params[:subscription_id]

      options[:filters] << {:terms => {:id => ids}}
      options[:filters] << {:term => {:name => params[:name].downcase}} if params[:name]
      options[:filters] << {:term => {:enabled => params[:enabled].to_bool}} if params[:enabled]
      options.merge!(sort_params)
      respond(:collection => item_search(Product, params, options))
    end

    api :POST, "/products", N_("Create a product")
    param :organization_id, :number, N_("ID of the organization"), :required => true
    param_group :product
    param :name, String, :desc => N_("Product name"), :required => true
    param :label, String, :required => false
    def create
      params[:product][:label] = labelize_params(product_params) if product_params

      product = Product.new(product_params)

      sync_task(::Actions::Katello::Product::Create, product, @organization)
      respond(:resource => product)
    end

    api :GET, "/products/:id", N_("Show a product")
    param :id, :number, :desc => N_("product numeric identifier"), :required => true
    def show
      respond_for_show(:resource => @product)
    end

    api :PUT, "/products/:id", N_("Updates a product")
    param :id, :number, :desc => N_("product numeric identifier"), :required => true, :allow_nil => false
    param_group :product
    param :name, String, :desc => N_("Product name")
    def update
      reset_gpg_keys = (product_params[:gpg_key_id] != @product.gpg_key_id)
      @product.reset_repo_gpgs! if reset_gpg_keys
      @product.update_attributes!(product_params)

      respond(:resource => @product.reload)
    end

    api :DELETE, "/products/:id", N_("Destroy a product")
    param :id, :number, :desc => N_("product numeric identifier")
    def destroy
      @product.destroy

      respond
    end

    api :POST, "/products/:id/sync", "Sync a repository"
    param :id, :identifier, :required => true, :desc => "product ID"
    def sync
      respond_for_async(:resource => @product.sync)
    end

    protected

    def find_product
      @product = Product.find_by_id(params[:id]) if params[:id]
    end

    def filter_by_subscription(ids = [], subscription_id = nil)
      @subscription = Pool.find_by_organization_and_id!(@organization, subscription_id)
      ids + @subscription.products.pluck("#{Product.table_name}.id")
    end

    def product_params
      # only allow sync plan id to be updated if the product is a Red Hat product
      if @product && @product.redhat?
        params.require(:product).permit(:sync_plan_id)
      else
        params.require(:product).permit(:name, :label, :description, :provider_id, :gpg_key_id, :sync_plan_id)
      end
    end

  end
end
